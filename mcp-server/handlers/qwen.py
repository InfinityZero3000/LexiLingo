"""
Qwen Handler - Chat AI model via ai-service proxy

Instead of loading the heavy Qwen model locally, this handler
proxies requests to ai-service at localhost:8001. When ai-service
is unavailable, it falls back to Gemini API.
"""

import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


class QwenHandler:
    """Handler for Qwen via ai-service proxy"""

    def __init__(self):
        self.loaded = False
        self._session_id = None

    async def load(self):
        """Check ai-service availability"""
        if self.loaded:
            return

        from utils.api_client import check_ai_service_health

        available = await check_ai_service_health()
        if available:
            logger.info("Qwen handler ready (proxying to ai-service)")
        else:
            logger.warning(
                "ai-service not available; Qwen will fall back to Gemini"
            )

        self.loaded = True

    async def chat(self, message: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate chat response via ai-service, with Gemini fallback.

        Args:
            message: User message
            context: Conversation context

        Returns:
            text: Generated response
            confidence: Confidence score
            suggestions: Learning suggestions
        """
        if not self.loaded:
            await self.load()

        user_level = context.get("user_level", "B1")

        try:
            from utils.api_client import call_ai_service

            # Create session if needed
            if not self._session_id:
                session_resp = await call_ai_service(
                    "POST",
                    "/api/v1/chat/sessions",
                    json={
                        "user_id": context.get("user_id", "mcp-user"),
                        "metadata": {"source": "mcp-server", "level": user_level},
                    },
                )
                # Response structure: {"success": true, "data": {"session_id": ...}}
                self._session_id = session_resp.get("data", session_resp).get("session_id")

            # Send message
            result = await call_ai_service(
                "POST",
                "/api/v1/chat/messages",
                json={
                    "session_id": self._session_id,
                    "message": message,
                    "user_id": context.get("user_id", "mcp-user"),
                },
            )

            # Response structure: {"success": true, "data": {"ai_response": ...}}
            data = result.get("data", result)
            return {
                "text": data.get("ai_response", data.get("response", data.get("message", ""))),
                "confidence": 0.90,
                "suggestions": data.get("suggestions", []),
            }

        except (ConnectionError, Exception) as e:
            if isinstance(e, ConnectionError):
                logger.info("ai-service unavailable, falling back to Gemini")
            else:
                logger.warning(f"ai-service error ({e}), falling back to Gemini")

            from handlers.gemini import GeminiHandler

            gemini = GeminiHandler()
            return await gemini.chat(message, context)

    async def unload(self):
        """Reset handler state"""
        self._session_id = None
        self.loaded = False
        logger.info("Qwen handler reset")
