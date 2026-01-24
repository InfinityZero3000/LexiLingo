"""Text-to-Speech (TTS) service using Piper."""

from __future__ import annotations

import io
import logging
from typing import Optional

from api.core.config import settings

logger = logging.getLogger(__name__)


class TTSService:
    def __init__(self) -> None:
        self._voice = None

    def _load_voice(self):
        if self._voice is not None:
            return self._voice

        try:
            from piper import PiperVoice  # type: ignore
        except Exception as exc:  # pragma: no cover - runtime dependency
            raise RuntimeError(
                "Piper is not installed. Add 'piper-tts' to requirements."
            ) from exc

        model_path = settings.TTS_MODEL_PATH
        config_path = settings.TTS_CONFIG_PATH

        logger.info(f"Loading TTS model: {model_path}")
        self._voice = PiperVoice.load(model_path, config_path=config_path)
        return self._voice

    def synthesize(self, text: str) -> bytes:
        voice = self._load_voice()
        wav_io = io.BytesIO()
        voice.synthesize(text, wav_io, speaker_id=settings.TTS_SPEAKER_ID)
        return wav_io.getvalue()


_tts_service: Optional[TTSService] = None


def get_tts_service() -> TTSService:
    global _tts_service
    if _tts_service is None:
        _tts_service = TTSService()
    return _tts_service
