from __future__ import annotations

import json
from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.generate as generate


class _FakeStreamResponse:
    def __init__(self, status_code: int, lines: list[str]) -> None:
        self.status_code = status_code
        self._lines = lines

    async def aiter_lines(self):
        for line in self._lines:
            yield line


class _FakeStreamCtx:
    """Stands in for `httpx.AsyncClient.stream(...)`'s async context manager."""

    def __init__(self, response: _FakeStreamResponse) -> None:
        self._response = response

    async def __aenter__(self):
        return self._response

    async def __aexit__(self, *exc):
        return False


class _FakeHttpxClient:
    def __init__(self, response: _FakeStreamResponse) -> None:
        self._response = response

    def stream(self, *args, **kwargs):
        return _FakeStreamCtx(self._response)


def _groq_sse(*deltas: str) -> list[str]:
    lines = [
        f"data: {json.dumps({'choices': [{'delta': {'content': d}}]})}"
        for d in deltas
    ]
    lines.append("data: [DONE]")
    return lines


def _gemini_sse(*texts: str) -> list[str]:
    return [
        f"data: {json.dumps({'candidates': [{'content': {'parts': [{'text': t}]}}]})}"
        for t in texts
    ]


@pytest.mark.asyncio
async def test_provider_info_reports_groq_when_groq_serves_tokens(monkeypatch):
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda name: False)
    monkeypatch.setattr(
        "api.core.groq_key_pool.try_acquire_groq_key", AsyncMock(return_value="fake-groq-key")
    )
    monkeypatch.setattr("api.core.groq_key_pool.release_groq_key", AsyncMock())
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())
    monkeypatch.setenv("GROQ_MODEL", "llama-3.1-8b-instant")
    fake_response = _FakeStreamResponse(200, _groq_sse("Hello", " world"))
    monkeypatch.setattr(
        generate, "_get_httpx_client", lambda name: _FakeHttpxClient(fake_response)
    )

    provider_info: dict = {}
    tokens = [
        token
        async for token in generate.stream_llm_tokens(
            system_prompt="sys",
            messages=[],
            user_input="hi",
            provider_info=provider_info,
        )
    ]

    assert "".join(tokens) == "Hello world"
    assert provider_info == {"provider": "groq", "model": "llama-3.1-8b-instant"}


@pytest.mark.asyncio
async def test_provider_info_reports_gemini_when_groq_yields_nothing(monkeypatch):
    """Groq admitted the key but its stream returned zero tokens (e.g. a
    non-200 status) — the turn must fall back to Gemini, and provider_info
    must reflect Gemini, not silently keep pointing at Groq."""
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda name: False)
    monkeypatch.setattr(
        "api.core.groq_key_pool.try_acquire_groq_key", AsyncMock(return_value="fake-groq-key")
    )
    monkeypatch.setattr("api.core.groq_key_pool.release_groq_key", AsyncMock())
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())
    monkeypatch.setenv("GEMINI_API_KEY", "fake-gemini-key")

    groq_failure_response = _FakeStreamResponse(500, [])
    gemini_response = _FakeStreamResponse(200, _gemini_sse("Xin ", "chào"))

    def _fake_client(name: str):
        return _FakeHttpxClient(groq_failure_response if name == "groq" else gemini_response)

    monkeypatch.setattr(generate, "_get_httpx_client", _fake_client)

    provider_info: dict = {}
    tokens = [
        token
        async for token in generate.stream_llm_tokens(
            system_prompt="sys",
            messages=[],
            user_input="hi",
            provider_info=provider_info,
        )
    ]

    assert "".join(tokens) == "Xin chào"
    assert provider_info == {"provider": "gemini", "model": "gemini-2.0-flash"}
