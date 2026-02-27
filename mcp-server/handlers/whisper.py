"""
Whisper Handler - Speech-to-Text via ai-service proxy

Proxies transcription requests to ai-service at localhost:8001.
Requires ai-service to be running with Whisper model loaded.
"""

import io
import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


class WhisperHandler:
    """Handler for Whisper STT via ai-service proxy"""

    def __init__(self):
        self.loaded = False

    async def load(self):
        """Check ai-service availability"""
        if self.loaded:
            return

        from utils.api_client import check_ai_service_health

        available = await check_ai_service_health()
        if available:
            logger.info("Whisper handler ready (proxying to ai-service)")
        else:
            logger.warning("ai-service not available; STT will not work")

        self.loaded = True

    async def transcribe(
        self,
        audio,
        language: str = "en",
        word_timestamps: bool = True,
    ) -> Dict[str, Any]:
        """
        Transcribe audio via ai-service STT endpoint.

        Args:
            audio: Audio numpy array (16kHz) or raw bytes
            language: Language code
            word_timestamps: Include word-level timestamps

        Returns:
            text: Transcribed text
            segments: Word segments with timestamps
            language: Detected language
            confidence: Average confidence
        """
        if not self.loaded:
            await self.load()

        try:
            import numpy as np
            import soundfile as sf
            from utils.api_client import call_ai_service

            # Convert numpy array to WAV bytes for upload
            if isinstance(audio, np.ndarray):
                buffer = io.BytesIO()
                sf.write(buffer, audio, 16000, format="WAV")
                wav_bytes = buffer.getvalue()
            else:
                wav_bytes = audio

            # Call ai-service STT endpoint
            result = await call_ai_service(
                "POST",
                "/api/v1/stt/transcribe",
                files={"file": ("audio.wav", wav_bytes, "audio/wav")},
            )

            return {
                "text": result.get("text", ""),
                "segments": result.get("segments", []),
                "language": result.get("language", language),
                "confidence": result.get("confidence", 0.0),
            }

        except ConnectionError:
            logger.error("ai-service not available for STT")
            return {
                "text": "",
                "error": "ai-service not available. Start it on port 8001 for STT.",
                "segments": [],
                "language": language,
                "confidence": 0.0,
            }
        except ImportError as e:
            logger.error(f"Missing dependency for STT: {e}")
            return {
                "text": "",
                "error": f"Missing dependency: {e}. Run: pip install numpy soundfile",
                "segments": [],
                "language": language,
                "confidence": 0.0,
            }
        except Exception as e:
            logger.error(f"Transcription error: {e}")
            raise

    async def unload(self):
        """Reset handler"""
        self.loaded = False
        logger.info("Whisper handler reset")
