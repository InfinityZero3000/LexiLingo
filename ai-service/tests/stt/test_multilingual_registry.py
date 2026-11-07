import asyncio

import pytest

from api.services.stt.config import STTConfig
from api.services.stt.engines.faster_whisper import WhisperChunkSession
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.schemas import AudioSegment
from tests.stt.fakes import FakePrimary, FakeVerifier


class _BlockingVerifier(FakeVerifier):
    def __init__(self):
        super().__init__()
        self.active = 0
        self.max_active = 0
        self.release = asyncio.Event()

    async def verify(self, audio, language):
        self.active += 1
        self.max_active = max(self.max_active, self.active)
        await self.release.wait()
        try:
            return await super().verify(audio, language)
        finally:
            self.active -= 1


@pytest.mark.asyncio
async def test_non_english_session_uses_multilingual_whisper(tmp_path):
    primary = FakePrimary()
    verifier = FakeVerifier()
    registry = STTModelRegistry(
        STTConfig(temp_dir=str(tmp_path)),
        primary=primary,
        verifier=verifier,
    )
    await registry.start()

    english = await registry.create_primary_session("en")
    vietnamese = await registry.create_primary_session("vi")

    assert english is primary.session
    assert isinstance(vietnamese, WhisperChunkSession)
    assert vietnamese.verifier is registry
    assert vietnamese.language == "vi"

    result = await vietnamese.finalize(
        AudioSegment(pcm16=b"\x00\x00" * 1600, start_ms=0, end_ms=100)
    )
    assert verifier.last_language == "vi"
    assert result.language == "vi"


@pytest.mark.asyncio
async def test_multilingual_primary_respects_verify_concurrency_limit(tmp_path):
    verifier = _BlockingVerifier()
    registry = STTModelRegistry(
        STTConfig(temp_dir=str(tmp_path), max_verify_concurrency=2),
        primary=FakePrimary(),
        verifier=verifier,
    )
    await registry.start()
    audio = AudioSegment(pcm16=b"\x00\x00" * 1600, start_ms=0, end_ms=100)
    sessions = [await registry.create_primary_session("vi") for _ in range(3)]
    tasks = [asyncio.create_task(session.finalize(audio)) for session in sessions]

    await asyncio.sleep(0.01)
    assert verifier.max_active == 2
    verifier.release.set()
    await asyncio.gather(*tasks)
