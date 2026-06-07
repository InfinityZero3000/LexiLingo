"""Text-to-Speech (TTS) service using Piper."""

from __future__ import annotations

import io
import logging
import os
import wave
from pathlib import Path
from typing import Optional

from api.core.config import settings

# Absolute path to the ai-service root (2 levels up from api/services/)
_SERVICE_ROOT = Path(__file__).resolve().parent.parent.parent

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

        # Support both absolute model paths and voice IDs like "en_US-lessac-medium".
        # Use _SERVICE_ROOT (absolute) so paths resolve correctly regardless of CWD.
        model_candidates = [
            model_path,
            f"{model_path}.onnx",
            str(_SERVICE_ROOT / "models" / "piper" / model_path),
            str(_SERVICE_ROOT / "models" / "piper" / f"{model_path}.onnx"),
            os.path.join("models", "piper", model_path),
            os.path.join("models", "piper", f"{model_path}.onnx"),
        ]

        resolved_model_path = next(
            (candidate for candidate in model_candidates if candidate and os.path.exists(candidate)),
            model_path,
        )

        resolved_config_path: Optional[str] = None
        if config_path:
            resolved_config_path = config_path
        else:
            json_candidates = [
                f"{resolved_model_path}.json",
                resolved_model_path.replace(".onnx", ".onnx.json"),
                str(_SERVICE_ROOT / "models" / "piper" / f"{Path(model_path).stem}.onnx.json"),
            ]
            resolved_config_path = next(
                (candidate for candidate in json_candidates if os.path.exists(candidate)),
                None,
            )

        logger.info(f"Loading TTS model: {resolved_model_path}")
        self._voice = PiperVoice.load(
            resolved_model_path,
            config_path=resolved_config_path,
        )
        return self._voice

    def synthesize(self, text: str) -> bytes:
        voice = self._load_voice()

        # Newer piper-tts versions return AudioChunk iterables.
        chunks = list(voice.synthesize(text))
        if chunks:
            wav_io = io.BytesIO()
            with wave.open(wav_io, "wb") as wav_file:
                wav_file.setnchannels(chunks[0].sample_channels)
                wav_file.setsampwidth(chunks[0].sample_width)
                wav_file.setframerate(chunks[0].sample_rate)
                for chunk in chunks:
                    wav_file.writeframes(chunk.audio_int16_bytes)
            return wav_io.getvalue()

        # Keep compatibility with older piper APIs that write into a buffer.
        wav_io = io.BytesIO()
        try:
            voice.synthesize(text, wav_io, speaker_id=settings.TTS_SPEAKER_ID)
        except TypeError:
            voice.synthesize(text, wav_io)
        return wav_io.getvalue()


_tts_service: Optional[TTSService] = None


def get_tts_service() -> TTSService:
    global _tts_service
    if _tts_service is None:
        _tts_service = TTSService()
    return _tts_service
