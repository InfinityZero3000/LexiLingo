"""Single-process lifecycle for STT model weights."""

from __future__ import annotations

import asyncio
import logging

from api.services.stt.config import STTConfig
from api.services.stt.engines.faster_whisper import (
    FasterWhisperVerifier,
    WhisperChunkPrimary,
)
from api.services.stt.engines.moonshine import MoonshinePrimary
from api.services.stt.engines.sherpa import SherpaPrimary
from api.services.stt.schemas import AudioSegment, VerificationResult
from api.services.stt.vad_endpointing import EnergyEndpointDetector, SileroVADFactory

logger = logging.getLogger(__name__)


class STTModelRegistry:
    def __init__(self, config: STTConfig, primary=None, verifier=None):
        self.config = config
        self.verifier = verifier or FasterWhisperVerifier(
            config.verify_model,
            config.verify_device,
            config.verify_compute_type,
            config.verify_beam_size,
        )
        self.primary = primary or MoonshinePrimary(config.primary_model)
        self.status = "unavailable"
        self.verifier_status = (
            "disabled" if not config.verify_enabled else "unavailable"
        )
        self.vad_status = "fallback"
        self._vad_factory = SileroVADFactory(config.silero_model_path)
        self._verify_sem = asyncio.Semaphore(config.max_verify_concurrency)

    async def start(self) -> None:
        if not self.config.enabled:
            self.status = "disabled"
            return
        if self.config.vad_engine == "silero":
            try:
                await self._vad_factory.load()
                self.vad_status = "silero"
            except Exception as exc:
                logger.warning("Silero VAD unavailable; using energy fallback: %s", exc)
        try:
            await self.primary.load()
            self.status = "ready"
        except Exception as exc:
            logger.warning("Moonshine unavailable, evaluating degraded mode: %s", exc)
            if not self.config.degraded_whisper_primary:
                self.status = "unavailable"
                return
            if self.config.fallback_primary_engine == "sherpa":
                try:
                    self.primary = SherpaPrimary(self.config.sherpa_model_dir)
                    await self.primary.load()
                    self.status = "degraded"
                except Exception as sherpa_exc:
                    logger.warning("Sherpa fallback unavailable: %s", sherpa_exc)
            if self.status == "unavailable":
                try:
                    await self.verifier.load()
                    self.verifier_status = "ready"
                    self.primary = WhisperChunkPrimary(self.verifier)
                    self.status = "degraded"
                except Exception as verifier_exc:
                    logger.warning("Faster-Whisper unavailable: %s", verifier_exc)
                    self.status = "unavailable"
        if self.config.verify_enabled and self.verifier_status != "ready":
            try:
                await self.verifier.load()
                self.verifier_status = "ready"
            except Exception as verifier_exc:
                logger.warning(
                    "Verifier preload failed; continuing without it: %s", verifier_exc
                )

    def create_vad(self):
        if self.vad_status == "silero":
            return self._vad_factory.create(self.config)
        return EnergyEndpointDetector(self.config)

    async def create_primary_session(self, language: str):
        if self.status not in {"ready", "degraded"}:
            raise RuntimeError("STT primary model is not ready")
        return await self.primary.create_session(language)

    async def verify(self, audio: AudioSegment, language: str) -> VerificationResult:
        async with self._verify_sem:
            return await asyncio.wait_for(
                self.verifier.verify(audio, language),
                timeout=self.config.verify_timeout_ms / 1000,
            )

    async def close(self) -> None:
        await self.primary.close()
        if self.verifier is not self.primary:
            await self.verifier.close()
