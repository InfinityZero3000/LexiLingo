"""Turn primary and verifier results into immutable final events."""

from __future__ import annotations

import time
from uuid import uuid4

from api.services.stt.config import STTConfig
from api.services.stt.schemas import (
    AudioSegment,
    FinalTranscriptEvent,
    PrimaryResult,
    UseCase,
)
from api.services.stt.transcript_normalizer import normalize_transcript
from api.services.stt.verifier_router import VerifierRouter


class SentenceFinalizer:
    def __init__(self, config: STTConfig, registry, metrics=None):
        self.config = config
        self.registry = registry
        self.router = VerifierRouter(config)
        self.metrics = metrics

    async def finalize(
        self,
        session_id: str,
        turn_id: str,
        use_case: UseCase,
        language: str,
        audio: AudioSegment,
        primary: PrimaryResult,
        utterance_id: str | None = None,
        user_id: str | None = None,
    ) -> FinalTranscriptEvent | None:
        decision = self.router.decide(primary, audio.duration_ms, use_case)
        selected = primary
        source = primary.source
        verified = False
        uncertain = primary.confidence < 0.70
        if decision.verify and self.config.verify_enabled:
            try:
                t0 = time.monotonic()
                verifier = await self.registry.verify(audio, language)
                if self.metrics:
                    self.metrics.record_latency(
                        "stt_verify_latency_ms",
                        (time.monotonic() - t0) * 1000,
                    )
                verified = True
                if verifier.text and (
                    verifier.confidence >= primary.confidence
                    or not primary.text.strip()
                ):
                    selected = verifier
                    source = verifier.source
                uncertain = selected.confidence < 0.70
            except Exception:
                source = f"{primary.source}_only"
                uncertain = primary.confidence < self.config.confidence_verify
        preserve = use_case == UseCase.PRONUNCIATION_SCORING
        text, rules = normalize_transcript(selected.text, preserve_exact=preserve)
        if not text:
            return None
        return FinalTranscriptEvent(
            session_id=session_id,
            user_id=user_id,
            utterance_id=utterance_id or f"utt_{uuid4().hex[:12]}",
            turn_id=turn_id,
            text=text,
            original_text=selected.text if rules else None,
            start_ms=audio.start_ms,
            end_ms=audio.end_ms,
            confidence=selected.confidence,
            confidence_source=selected.confidence_source,
            source=source,
            verified=verified,
            uncertain=uncertain,
            needs_confirmation=uncertain,
            language=selected.language or language,
            verify_reason=decision.reason,
        )
