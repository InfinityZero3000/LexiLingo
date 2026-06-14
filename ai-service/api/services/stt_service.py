"""Compatibility façade over the unified STT model registry."""

from __future__ import annotations

from typing import Optional

from api.services.stt.runtime import get_stt_registry


class STTService:
    async def transcribe_file(self, audio_path: str, language: Optional[str] = None):
        registry = get_stt_registry()
        result = await registry.verifier.transcribe_path(audio_path, language or "en")
        return result.model_dump()


_service = STTService()


def get_stt_service() -> STTService:
    return _service
