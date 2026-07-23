import asyncio
from types import SimpleNamespace
from threading import Event
from unittest.mock import AsyncMock

import pytest

from api.services.stt.sentence_splitter import split_speakable_fragments
from api.services.stt.streaming_tts import StreamingTTS, TTSBusyError
from api.services.tts_service import TTSService
from api.services.trace_cag import generate


def test_sentence_fragments_prefer_boundaries_and_respect_limit():
    fragments = list(
        split_speakable_fragments(
            "Hello, world! This is a longer sentence for testing.", 16
        )
    )
    assert fragments == ["Hello, world!", "This is a longer", "sentence for", "testing."]
    assert all(len(fragment) <= 16 for fragment in fragments)
    assert len(next(split_speakable_fragments("abcdefghijklmnop. tail", 16))) == 16


def test_tts_pcm_is_lazy_and_keeps_fragment_order():
    spoken = []

    class Voice:
        def synthesize(self, fragment):
            spoken.append(fragment)
            return [SimpleNamespace(audio_int16_bytes=fragment.encode())]

    service = TTSService()
    service._voice = Voice()
    chunks = service.iter_pcm_chunks("First sentence. Second sentence.", max_fragment_chars=16)

    assert next(chunks) == b"First sentence."
    assert spoken == ["First sentence."]
    assert list(chunks) == [b"Second sentence."]


@pytest.mark.asyncio
async def test_streaming_tts_rejects_when_capacity_is_active():
    service = SimpleNamespace(iter_pcm_chunks=lambda _text: iter((b"first", b"second")))
    runtime = StreamingTTS(service=service, capacity=1)
    active = runtime.stream("one")

    assert await anext(active) == b"first"
    with pytest.raises(TTSBusyError):
        await anext(runtime.stream("two"))
    await active.aclose()
    admitted = runtime.stream("three")
    assert await anext(admitted) == b"first"
    await admitted.aclose()


@pytest.mark.asyncio
async def test_streaming_tts_cancellation_holds_slot_until_worker_finishes():
    started = Event()
    finish = Event()

    def blocking_chunks(_text):
        def chunks():
            started.set()
            finish.wait()
            yield b"pcm"

        return chunks()

    runtime = StreamingTTS(
        service=SimpleNamespace(iter_pcm_chunks=blocking_chunks), capacity=1
    )
    active = asyncio.create_task(anext(runtime.stream("one")))
    assert await asyncio.to_thread(started.wait, 1)
    active.cancel()

    with pytest.raises(TTSBusyError):
        await anext(runtime.stream("two"))
    finish.set()
    with pytest.raises(asyncio.CancelledError):
        await active


@pytest.mark.asyncio
async def test_stream_llm_tokens_forwards_max_tokens_to_providers(monkeypatch):
    payloads = {}

    class Response:
        status_code = 200

        def __init__(self, provider):
            self.provider = provider

        async def aiter_lines(self):
            if self.provider == "groq":
                yield 'data: {"choices":[{"delta":{"content":"Hi"}}]}'
            else:
                yield 'data: {"candidates":[{"content":{"parts":[{"text":"Hi"}]}}]}'

    class Stream:
        def __init__(self, provider):
            self.provider = provider

        async def __aenter__(self):
            return Response(self.provider)

        async def __aexit__(self, *_args):
            return False

    class Client:
        def __init__(self, provider):
            self.provider = provider

        def stream(self, *_args, **kwargs):
            payloads[self.provider] = kwargs["json"]
            return Stream(self.provider)

    monkeypatch.setattr(
        "api.core.groq_key_pool.try_acquire_groq_key", AsyncMock(return_value="key")
    )
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())
    monkeypatch.setattr("api.core.groq_key_pool.release_groq_key", AsyncMock())
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda _provider: False)
    monkeypatch.setattr(generate, "_get_httpx_client", Client)

    tokens = [
        token
        async for token in generate.stream_llm_tokens(
            system_prompt="system",
            messages=[{"role": "user", "content": "hello"}],
            user_input="hello",
            max_tokens=96,
        )
    ]

    assert tokens == ["Hi"]
    assert payloads["groq"]["max_tokens"] == 96

    monkeypatch.setattr(
        "api.core.groq_key_pool.try_acquire_groq_key", AsyncMock(return_value=None)
    )
    monkeypatch.setenv("GEMINI_API_KEY", "key")
    tokens = [
        token
        async for token in generate.stream_llm_tokens(
            system_prompt="system", messages=[], user_input="hello", max_tokens=96
        )
    ]
    assert tokens == ["Hi"]
    assert payloads["gemini"]["generationConfig"]["maxOutputTokens"] == 96


@pytest.mark.asyncio
async def test_voice_llm_busy_error_is_only_for_pre_admission(monkeypatch):
    async def consume():
        return [
            token
            async for token in generate.stream_llm_tokens(
                system_prompt="system",
                messages=[],
                user_input="hello",
                allow_gemini_fallback=False,
            )
        ]

    monkeypatch.setattr(
        "api.core.groq_key_pool.try_acquire_groq_key", AsyncMock(return_value=None)
    )
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda _provider: False)
    with pytest.raises(generate.ProviderBusyError):
        await consume()

    class FailedResponse:
        status_code = 500

    class Stream:
        async def __aenter__(self):
            return FailedResponse()

        async def __aexit__(self, *_args):
            return False

    monkeypatch.setattr(
        "api.core.groq_key_pool.try_acquire_groq_key", AsyncMock(return_value="key")
    )
    monkeypatch.setattr("api.core.groq_key_pool.release_groq_key", AsyncMock())
    monkeypatch.setattr(
        generate,
        "_get_httpx_client",
        lambda _provider: SimpleNamespace(stream=lambda *_args, **_kwargs: Stream()),
    )
    with pytest.raises(RuntimeError, match="admitted"):
        await consume()


@pytest.mark.asyncio
async def test_disabled_groq_provider_does_not_reserve_key(monkeypatch):
    acquire = AsyncMock(return_value="key")
    monkeypatch.setattr("api.core.groq_key_pool.try_acquire_groq_key", acquire)
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda provider: provider == "groq")

    with pytest.raises(generate.ProviderBusyError):
        async for _ in generate.stream_llm_tokens(
            system_prompt="system",
            messages=[],
            user_input="hello",
            allow_gemini_fallback=False,
        ):
            pass

    acquire.assert_not_awaited()


@pytest.mark.asyncio
async def test_accounting_failure_does_not_break_early_close_or_release(monkeypatch):
    events = []
    timeouts = []

    class Response:
        status_code = 200

        async def aiter_lines(self):
            yield 'data: {"choices":[{"delta":{"content":"Hi"}}]}'
            yield 'data: {"choices":[{"delta":{"content":"later"}}]}'

    class Stream:
        async def __aenter__(self):
            return Response()

        async def __aexit__(self, *_args):
            return False

    async def record(*_args):
        events.append("record")
        raise RuntimeError("accounting down")

    async def release(*_args):
        events.append("release")

    class Timeout:
        async def __aenter__(self):
            return None

        async def __aexit__(self, *_args):
            return False

    def timeout(seconds):
        timeouts.append(seconds)
        return Timeout()

    monkeypatch.setattr(
        "api.core.groq_key_pool.try_acquire_groq_key", AsyncMock(return_value="key")
    )
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", record)
    monkeypatch.setattr("api.core.groq_key_pool.release_groq_key", release)
    monkeypatch.setattr(generate, "_provider_is_disabled", lambda _provider: False)
    monkeypatch.setattr(generate, "asyncio", SimpleNamespace(timeout=timeout))
    monkeypatch.setattr(
        generate,
        "_get_httpx_client",
        lambda _provider: SimpleNamespace(stream=lambda *_args, **_kwargs: Stream()),
    )

    tokens = generate.stream_llm_tokens(
        system_prompt="system", messages=[], user_input="hello"
    )
    assert await anext(tokens) == "Hi"
    await tokens.aclose()

    assert events == ["record", "release"]
    assert timeouts == [30.0]
