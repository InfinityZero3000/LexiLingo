from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from api.services.stt.sentence_splitter import split_speakable_fragments
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
        "api.core.groq_key_pool.get_available_groq_key", AsyncMock(return_value="key")
    )
    monkeypatch.setattr("api.core.groq_key_pool.record_groq_key_usage", AsyncMock())
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
        "api.core.groq_key_pool.get_available_groq_key", AsyncMock(return_value=None)
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
