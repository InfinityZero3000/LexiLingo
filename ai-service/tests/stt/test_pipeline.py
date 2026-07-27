import pytest

from api.services.stt.config import STTConfig
from api.services.stt.metrics import STTMetrics
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.schemas import AudioSegment, PrimaryResult, UseCase
from api.services.stt.sentence_finalizer import SentenceFinalizer
from api.services.stt.vad_endpointing import EnergyEndpointDetector
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


@pytest.mark.asyncio
async def test_verifier_failure_marks_uncertain_and_source_only(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path))
    registry = STTModelRegistry(
        config, primary=FakePrimary(), verifier=FakeVerifier(fail=True)
    )
    finalizer = SentenceFinalizer(config, registry)
    audio = AudioSegment(pcm16=b"\x00\x00" * 8000, start_ms=0, end_ms=1000)
    primary = PrimaryResult(
        text="hello", confidence=0.5, confidence_source="fake", source="fake-primary"
    )
    event = await finalizer.finalize("s1", "t1", UseCase.CONVERSATION, "en", audio, primary)
    assert event is not None
    assert event.uncertain is True
    assert event.source == "fake-primary_only"


@pytest.mark.asyncio
async def test_finalizer_drops_noise_utterance(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), verify_enabled=False)
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    finalizer = SentenceFinalizer(config, registry)
    result = await finalizer.finalize(
        "s1",
        "t1",
        UseCase.CONVERSATION,
        "en",
        AudioSegment(pcm16=b"\x00\x00" * 8000, start_ms=0, end_ms=1000),
        PrimaryResult(text="um", confidence=0.9, confidence_source="fake", source="fake-primary"),
    )
    assert result is None


def test_router_always_verifies_non_conversation_use_cases(tmp_path):
    router = VerifierRouter(STTConfig(temp_dir=str(tmp_path)))
    audio_duration_ms = 2000
    primary = PrimaryResult(
        text="hello world", confidence=0.9, confidence_source="fake", source="fake-primary"
    )
    for use_case in (UseCase.SPEAKING_PRACTICE, UseCase.PRONUNCIATION_SCORING):
        decision = router.decide(primary, audio_duration_ms, use_case)
        assert decision.verify, f"{use_case} should always trigger verification"
        assert decision.reason == "accuracy_sensitive_use_case"


@pytest.mark.asyncio
async def test_vad_fallback_to_energy_detector(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        vad_engine="silero",
        silero_model_path="/nonexistent/model.onnx",
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    await registry.start()
    assert registry.vad_status == "fallback"
    vad = registry.create_vad()
    assert isinstance(vad, EnergyEndpointDetector)
    assert registry.vad_fallback_count == 1


@pytest.mark.asyncio
async def test_metrics_records_verify_latency(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path))
    metrics = STTMetrics()
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    finalizer = SentenceFinalizer(config, registry, metrics)
    await finalizer.finalize(
        "s1",
        "t1",
        UseCase.CONVERSATION,
        "en",
        AudioSegment(pcm16=b"\x00\x00" * 8000, start_ms=0, end_ms=1000),
        PrimaryResult(
            text="hello", confidence=0.5, confidence_source="fake", source="fake-primary"
        ),
    )
    stats = metrics.latency_stats("stt_verify_latency_ms")
    assert stats["count"] == 1
    assert stats["avg"] >= 0
