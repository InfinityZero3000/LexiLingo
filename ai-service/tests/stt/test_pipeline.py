import pytest

from api.services.stt.config import STTConfig
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.schemas import AudioSegment, PrimaryResult, UseCase
from api.services.stt.sentence_finalizer import SentenceFinalizer
from api.services.stt.verifier_router import VerifierRouter
from tests.stt.fakes import FakePrimary, FakeVerifier


@pytest.mark.asyncio
async def test_registry_enters_degraded_mode(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), fallback_primary_engine="none")
    verifier = FakeVerifier()
    registry = STTModelRegistry(
        config, primary=FakePrimary(fail_load=True), verifier=verifier
    )
    await registry.start()
    assert registry.status == "degraded"
    assert verifier.loads == 1


def test_router_verifies_low_confidence(tmp_path):
    router = VerifierRouter(STTConfig(temp_dir=str(tmp_path)))
    decision = router.decide(
        PrimaryResult(text="maybe", confidence=0.5), 1000, UseCase.CONVERSATION
    )
    assert decision.verify
    assert decision.reason == "low_confidence"


@pytest.mark.asyncio
async def test_finalizer_selects_better_verifier(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path))
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    finalizer = SentenceFinalizer(config, registry)
    event = await finalizer.finalize(
        "s1",
        "t1",
        UseCase.CONVERSATION,
        "en",
        AudioSegment(pcm16=b"\x00\x00" * 8000, start_ms=0, end_ms=1000),
        PrimaryResult(text="helo", confidence=0.5),
    )
    assert event.text == "verified text."
    assert event.verified is True
    assert event.source == "faster-whisper"
