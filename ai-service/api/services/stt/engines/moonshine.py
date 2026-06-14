"""Moonshine streaming adapter.

The native package API has changed across releases, so all package-specific
calls live here. Import or initialization failures are handled by the registry.
"""

from __future__ import annotations

import asyncio
from typing import Any

import numpy as np

from api.services.stt.schemas import AudioSegment, PrimaryResult


class MoonshineSession:
    def __init__(self, transcriber: Any, language: str):
        self._transcriber = transcriber
        self._language = language
        self._last_text = ""
        self._pending_ms = 0

    async def push_audio(self, pcm16: bytes, start_ms: int, end_ms: int):
        samples = np.frombuffer(pcm16, dtype="<i2").astype(np.float32) / 32768.0
        self._pending_ms += end_ms - start_ms

        await asyncio.to_thread(self._transcriber.add_audio, samples.tolist(), 16000)
        if self._pending_ms < 300:
            return None
        self._pending_ms = 0
        result = await asyncio.to_thread(self._transcriber.update_transcription)
        text = _extract_text(result)
        if not text or text == self._last_text:
            return None
        self._last_text = text
        return PrimaryResult(
            text=text,
            confidence=_stability_confidence(text),
            confidence_source="partial_stability",
            language=self._language,
            source="moonshine",
        )

    async def finalize(self, audio: AudioSegment) -> PrimaryResult:
        result = await asyncio.to_thread(
            self._transcriber.update_transcription,
            self._transcriber.MOONSHINE_FLAG_FORCE_UPDATE,
        )
        text = _extract_text(result) or self._last_text
        return PrimaryResult(
            text=text,
            confidence=_stability_confidence(text),
            confidence_source="partial_stability",
            language=self._language,
            source="moonshine",
        )

    async def close(self) -> None:
        close = getattr(self._transcriber, "close", None)
        stop = getattr(self._transcriber, "stop", None)
        if stop:
            await asyncio.to_thread(stop)
        if close:
            await asyncio.to_thread(close)


class MoonshinePrimary:
    def __init__(self, model_name: str = "en"):
        self.model_name = model_name
        self._factory = None

    async def load(self) -> None:
        if self._factory is not None:
            return

        def _load():
            from moonshine_voice import ModelArch, Transcriber, get_model_for_language

            architectures = {
                "tiny": ModelArch.TINY,
                "base": ModelArch.BASE,
                "tiny_streaming": ModelArch.TINY_STREAMING,
                "base_streaming": ModelArch.BASE_STREAMING,
            }
            model_arch = architectures.get(self.model_name, ModelArch.TINY_STREAMING)
            model_path, model_arch = get_model_for_language("en", model_arch)

            def factory():
                transcriber = Transcriber(
                    model_path=model_path,
                    model_arch=model_arch,
                    update_interval=0.3,
                )
                transcriber.start()
                return transcriber

            return factory

        factory = await asyncio.to_thread(_load)

        def _probe():
            transcriber = factory()
            try:
                transcriber.stop()
            finally:
                transcriber.close()

        await asyncio.to_thread(_probe)
        self._factory = factory

    async def create_session(self, language: str) -> MoonshineSession:
        await self.load()
        return MoonshineSession(await asyncio.to_thread(self._factory), language)

    async def close(self) -> None:
        self._factory = None


def _extract_text(result: Any) -> str:
    if isinstance(result, str):
        return result.strip()
    if isinstance(result, dict):
        return str(result.get("text", "")).strip()
    lines = getattr(result, "lines", None)
    if lines:
        return " ".join(
            str(getattr(line, "text", "")).strip() for line in lines
        ).strip()
    return str(getattr(result, "text", "")).strip()


def _stability_confidence(text: str) -> float:
    if not text:
        return 0.0
    words = text.split()
    repeated = len(words) - len(set(word.lower() for word in words))
    penalty = min(0.25, repeated * 0.04)
    return max(0.55, min(0.9, 0.72 + min(len(words), 12) * 0.015 - penalty))
