"""What stream_llm_tokens hands the caller when a provider misbehaves.

test_stream_llm_tokens_provider_info covers the two happy paths. These cover the ways the
stream actually broke in production: an SSE error frame after a 200 header, non-200s,
junk lines, and no capacity at all.
"""

from __future__ import annotations

import json
from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.generate as generate


class _Resp:
    def __init__(self, status_code, lines):
        self.status_code, self._lines = status_code, lines

    async def aiter_lines(self):
        for line in self._lines:
            yield line


class _Ctx:
    def __init__(self, resp=None, exc=None):
        self._resp, self._exc = resp, exc

    async def __aenter__(self):
        if self._exc:
            raise self._exc
        return self._resp

    async def __aexit__(self, *a):
        return False


class _Client:
    def __init__(self, resp=None, exc=None):
        self._resp, self._exc = resp, exc

    def stream(self, *a, **k):
        return _Ctx(self._resp, self._exc)


def groq(*deltas):
    return [f"data: {json.dumps({'choices': [{'delta': {'content': d}}]})}" for d in deltas]


def gemini(*texts):
    return [f"data: {json.dumps({'candidates': [{'content': {'parts': [{'text': t}]}}]})}" for t in texts]


ERROR_FRAME = f"data: {json.dumps({'error': {'message': 'daily token quota exhausted'}})}"


@pytest.fixture
def rig(monkeypatch):
    """Groq admitted by default; hand each provider its own canned client."""
    r = type("Rig", (), {})()
    r.acquire = AsyncMock(return_value="key-1")
    r.release = AsyncMock()
    r.record = AsyncMock()
    r.clients = {}
    r.requested = []
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda name: False)
    monkeypatch.setattr("api.core.groq_key_pool.try_acquire_groq_key", r.acquire)
    monkeypatch.setattr("api.core.groq_key_pool.release_groq_key", r.release)
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", r.record)
    monkeypatch.setenv("GROQ_MODEL", "qwen/qwen3.8-27b")
    monkeypatch.setenv("GEMINI_API_KEY", "gem-key")

    def get_client(name):
        r.requested.append(name)
        return r.clients[name]

    monkeypatch.setattr(generate, "_get_httpx_client", get_client)
    return r


async def collect(**kw):
    info: dict = {}
    kw.setdefault("provider_info", info)
    out = [t async for t in generate.stream_llm_tokens(system_prompt="s", messages=[], user_input="hi", **kw)]
    return "".join(out), info


@pytest.mark.asyncio
async def test_error_frame_before_any_token_falls_back_to_gemini(rig):
    rig.clients["groq"] = _Client(_Resp(200, [ERROR_FRAME]))
    rig.clients["gemini"] = _Client(_Resp(200, gemini("from gemini")))
    text, info = await collect()
    assert text == "from gemini"
    assert info == {"provider": "gemini", "model": "gemini-2.0-flash"}


@pytest.mark.asyncio
async def test_error_frame_after_tokens_keeps_them_and_does_not_call_gemini(rig):
    rig.clients["groq"] = _Client(_Resp(200, groq("Hello", " there") + [ERROR_FRAME] + groq("never")))
    text, info = await collect()
    assert text == "Hello there"
    assert info["provider"] == "groq"
    assert "gemini" not in rig.requested


@pytest.mark.asyncio
async def test_non_200_falls_back_to_gemini(rig):
    rig.clients["groq"] = _Client(_Resp(429, []))
    rig.clients["gemini"] = _Client(_Resp(200, gemini("ok")))
    text, info = await collect()
    assert (text, info["provider"]) == ("ok", "gemini")


@pytest.mark.asyncio
async def test_junk_lines_and_empty_deltas_are_skipped(rig):
    lines = ["", ": keepalive", "event: ping", "data: {not json", *groq("A", "", "B"), "data: [DONE]", *groq("after")]
    rig.clients["groq"] = _Client(_Resp(200, lines))
    text, _ = await collect()
    assert text == "AB"


@pytest.mark.asyncio
async def test_null_content_delta_is_skipped(rig):
    lines = [f"data: {json.dumps({'choices': [{'delta': {'content': None}}]})}", *groq("x")]
    rig.clients["groq"] = _Client(_Resp(200, lines))
    text, _ = await collect()
    assert text == "x"


@pytest.mark.asyncio
async def test_no_groq_key_and_no_fallback_raises_provider_busy(rig):
    rig.acquire.return_value = None
    with pytest.raises(generate.ProviderBusyError):
        await collect(allow_gemini_fallback=False)
    assert rig.requested == []


@pytest.mark.asyncio
async def test_admitted_but_silent_without_fallback_raises_runtime_error_not_busy(rig):
    rig.clients["groq"] = _Client(_Resp(200, ["data: [DONE]"]))
    with pytest.raises(RuntimeError) as exc:
        await collect(allow_gemini_fallback=False)
    assert not isinstance(exc.value, generate.ProviderBusyError)


@pytest.mark.asyncio
async def test_no_groq_key_with_fallback_goes_straight_to_gemini(rig):
    rig.acquire.return_value = None
    rig.clients["gemini"] = _Client(_Resp(200, gemini("a", "b")))
    text, info = await collect()
    assert (text, info["provider"]) == ("ab", "gemini")
    assert rig.release.await_count == 0


@pytest.mark.asyncio
async def test_key_is_released_and_usage_recorded_when_the_connection_blows_up(rig):
    rig.clients["groq"] = _Client(exc=ConnectionError("reset"))
    rig.clients["gemini"] = _Client(_Resp(200, gemini("rescued")))
    text, _ = await collect()
    assert text == "rescued"
    rig.release.assert_awaited_once_with("key-1")
    rig.record.assert_awaited_once()


@pytest.mark.asyncio
async def test_key_is_released_after_a_normal_stream(rig):
    rig.clients["groq"] = _Client(_Resp(200, groq("hi")))
    await collect()
    rig.release.assert_awaited_once_with("key-1")


@pytest.mark.asyncio
async def test_usage_accounting_failure_still_releases_the_key(rig):
    rig.record.side_effect = RuntimeError("redis down")
    rig.clients["groq"] = _Client(_Resp(200, groq("hi")))
    text, _ = await collect()
    assert text == "hi"
    rig.release.assert_awaited_once_with("key-1")


@pytest.mark.asyncio
async def test_usage_is_never_recorded_below_the_floor(rig):
    rig.clients["groq"] = _Client(_Resp(200, groq("one")))
    await collect()
    assert rig.record.await_args.args[1] >= 50


@pytest.mark.asyncio
async def test_disabled_groq_is_not_even_acquired(rig, monkeypatch):
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda name: name == "groq")
    rig.clients["gemini"] = _Client(_Resp(200, gemini("g")))
    text, info = await collect()
    assert (text, info["provider"]) == ("g", "gemini")
    rig.acquire.assert_not_awaited()


@pytest.mark.asyncio
async def test_both_providers_silent_yields_nothing_and_leaves_provider_info_empty(rig):
    rig.clients["groq"] = _Client(_Resp(500, []))
    rig.clients["gemini"] = _Client(_Resp(500, []))
    text, info = await collect()
    assert text == ""
    assert info == {}


@pytest.mark.asyncio
async def test_gemini_without_api_key_is_skipped(rig, monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY")
    rig.clients["groq"] = _Client(_Resp(500, []))
    text, info = await collect()
    assert (text, info) == ("", {})
    assert "gemini" not in rig.requested


@pytest.mark.asyncio
async def test_gemini_malformed_chunk_is_skipped(rig):
    rig.acquire.return_value = None
    rig.clients["gemini"] = _Client(_Resp(200, ["data: nope", "data: {}", *gemini("ok")]))
    text, _ = await collect()
    assert text == "ok"


@pytest.mark.asyncio
async def test_closing_the_consumer_early_still_releases_the_key(rig):
    rig.clients["groq"] = _Client(_Resp(200, groq("a", "b", "c")))
    gen = generate.stream_llm_tokens(system_prompt="s", messages=[], user_input="hi")
    assert await gen.__anext__() == "a"
    await gen.aclose()
    rig.release.assert_awaited_once_with("key-1")


@pytest.mark.asyncio
async def test_error_frame_is_logged_with_its_message(rig, caplog):
    rig.clients["groq"] = _Client(_Resp(200, [ERROR_FRAME]))
    rig.clients["gemini"] = _Client(_Resp(200, gemini("ok")))
    with caplog.at_level("WARNING", logger=generate.logger.name):
        await collect()
    assert any("mid-stream error" in r.message and "quota exhausted" in r.message for r in caplog.records)
