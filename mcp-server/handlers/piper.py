"""
Piper Handler - Text-to-Speech via ai-service proxy

Proxies TTS requests to ai-service at localhost:8001.
Requires ai-service to be running with gTTS/Piper available.
"""

import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


class PiperHandler:
    """Handler for Piper TTS via ai-service proxy"""

    def __init__(self):
        self.loaded = False

    async def load(self):
        """Check ai-service availability"""
        if self.loaded:
            return

        from utils.api_client import check_ai_service_health

        available = await check_ai_service_health()
        if available:
            logger.info("Piper/TTS handler ready (proxying to ai-service)")
        else:
            logger.warning("ai-service not available; TTS will not work")

        self.loaded = True

    async def synthesize(
        self,
        text: str,
        voice_id: str = "en_US-lessac-medium",
        speed: float = 1.0,
    ) -> Dict[str, Any]:
        """
        Synthesize speech via ai-service TTS endpoint.

        Args:
            text: Text to synthesize
            voice_id: Voice identifier
            speed: Speech speed

        Returns:
            audio_bytes: Raw audio bytes
            duration: Estimated duration in seconds
            sample_rate: Audio sample rate
        """
        if not self.loaded:
            await self.load()

        try:
            from utils.api_client import AI_SERVICE_URL, get_client

            client = await get_client()
            resp = await client.post(
                f"{AI_SERVICE_URL}/api/v1/tts/synthesize",
                json={"text": text, "language": "en", "speed": speed},
            )
            resp.raise_for_status()

            audio_bytes = resp.content
            # Estimate duration: ~150 words per minute
            word_count = len(text.split())
            est_duration = max(word_count / 2.5, 0.5)

            return {
                "audio_bytes": audio_bytes,
                "duration": est_duration,
                "sample_rate": 22050,
            }

        except Exception as e:
            if "Connect" in type(e).__name__ or "Connection" in str(e):
                logger.error("ai-service not available for TTS")
                return {
                    "audio_bytes": b"",
                    "error": "ai-service not available. Start it on port 8001 for TTS.",
                    "duration": 0.0,
                    "sample_rate": 22050,
                }
            logger.error(f"TTS error: {e}")
            raise

    async def unload(self):
        """Reset handler"""
        self.loaded = False
        logger.info("Piper handler reset")
