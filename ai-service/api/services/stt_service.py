"""Speech-to-Text (STT) service using Faster-Whisper."""

from __future__ import annotations

import logging
from typing import Dict, Optional

from api.core.config import settings

logger = logging.getLogger(__name__)


class STTService:
    def __init__(self) -> None:
        self._model = None

    def _load_model(self):
        if self._model is not None:
            return self._model

        try:
            from faster_whisper import WhisperModel  # type: ignore
        except Exception as exc:  # pragma: no cover - runtime dependency
            raise RuntimeError(
                "Faster-Whisper is not installed. Add 'faster-whisper' to requirements."
            ) from exc

        model_name = settings.STT_MODEL_NAME
        device = settings.STT_DEVICE
        compute_type = settings.STT_COMPUTE_TYPE

        logger.info(f"Loading STT model: {model_name} on {device} ({compute_type})")
        self._model = WhisperModel(model_name, device=device, compute_type=compute_type)
        return self._model

    def transcribe_file(self, audio_path: str, language: Optional[str] = None) -> Dict[str, str]:
        model = self._load_model()
        segments, info = model.transcribe(
            audio_path,
            beam_size=settings.STT_BEAM_SIZE,
            language=language or settings.STT_LANGUAGE or None,
            vad_filter=settings.STT_VAD,
        )

        text = "".join(segment.text for segment in segments).strip()
        return {
            "text": text,
            "language": info.language if info else (language or ""),
        }


_stt_service: Optional[STTService] = None


def get_stt_service() -> STTService:
    global _stt_service
    if _stt_service is None:
        _stt_service = STTService()
    return _stt_service
