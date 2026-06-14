"""Shared Faster-Whisper verifier and degraded primary adapter."""

from __future__ import annotations

import asyncio
import math
import tempfile
import wave
from pathlib import Path

from api.services.stt.schemas import AudioSegment, PrimaryResult, VerificationResult


class FasterWhisperVerifier:
    def __init__(
        self,
        model_name: str,
        device: str,
        compute_type: str,
        beam_size: int = 1,
    ):
        self.model_name = model_name
        self.device = device
        self.compute_type = compute_type
        self.beam_size = beam_size
        self._model = None
        self._load_lock = asyncio.Lock()

    async def load(self) -> None:
        if self._model is not None:
            return
        async with self._load_lock:
            if self._model is not None:
                return
            from faster_whisper import WhisperModel

            self._model = await asyncio.to_thread(
                WhisperModel,
                self.model_name,
                device=self.device,
                compute_type=self.compute_type,
            )

    async def verify(self, audio: AudioSegment, language: str) -> VerificationResult:
        await self.load()
        return await asyncio.to_thread(self._transcribe, audio, language)

    async def transcribe_path(self, path: str, language: str) -> VerificationResult:
        await self.load()
        return await asyncio.to_thread(self._transcribe_path, path, language, 0)

    def _transcribe(self, audio: AudioSegment, language: str) -> VerificationResult:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as handle:
            path = Path(handle.name)
        try:
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16000)
                wav.writeframes(audio.pcm16)
            return self._transcribe_path(str(path), language, audio.start_ms)
        finally:
            path.unlink(missing_ok=True)

    def _transcribe_path(
        self, path: str, language: str, offset_ms: int
    ) -> VerificationResult:
        segments, info = self._model.transcribe(
            path,
            language=language,
            beam_size=self.beam_size,
            word_timestamps=True,
            vad_filter=False,
        )
        rows = []
        text = []
        probabilities = []
        for segment in segments:
            segment_text = segment.text.strip()
            no_speech_probability = float(
                getattr(segment, "no_speech_prob", 0.0) or 0.0
            )
            if no_speech_probability >= 0.6:
                continue
            if segment_text:
                text.append(segment_text)
            probability = math.exp(segment.avg_logprob) * (1.0 - no_speech_probability)
            probability = min(1.0, max(0.0, probability))
            probabilities.append(probability)
            rows.append(
                {
                    "text": segment_text,
                    "start_ms": int(segment.start * 1000) + offset_ms,
                    "end_ms": int(segment.end * 1000) + offset_ms,
                    "confidence": probability,
                }
            )
        confidence = sum(probabilities) / len(probabilities) if probabilities else 0.0
        return VerificationResult(
            text=" ".join(text),
            confidence=confidence,
            confidence_source="exp_avg_logprob",
            language=getattr(info, "language", language),
            source="faster-whisper",
            segments=rows,
        )

    async def close(self) -> None:
        self._model = None


class WhisperChunkSession:
    """Degraded primary session; emits final results only."""

    def __init__(self, verifier: FasterWhisperVerifier, language: str):
        self.verifier = verifier
        self.language = language

    async def push_audio(self, pcm16: bytes, start_ms: int, end_ms: int):
        return None

    async def finalize(self, audio: AudioSegment) -> PrimaryResult:
        result = await self.verifier.verify(audio, self.language)
        return PrimaryResult(**result.model_dump(exclude={"segments"}))

    async def close(self) -> None:
        return None


class WhisperChunkPrimary:
    def __init__(self, verifier: FasterWhisperVerifier):
        self.verifier = verifier

    async def load(self) -> None:
        await self.verifier.load()

    async def create_session(self, language: str) -> WhisperChunkSession:
        await self.load()
        return WhisperChunkSession(self.verifier, language)

    async def close(self) -> None:
        return None
