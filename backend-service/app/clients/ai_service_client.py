"""AI service client.

Purpose:
- Keep AI integration behind a small client boundary.
- Allow the backend-service to call ai-service later without refactoring routes.

This module is safe to include even when AI is not enabled.
"""

from __future__ import annotations

import logging
import os
from typing import Any, ClassVar, Optional

import httpx

from app.core.config import settings
from app.schemas.ai import AIChatRequest, AIChatResponse

logger = logging.getLogger(__name__)


async def diagnose_error(text: str, level: str | None = None) -> str | None:
    """Return the primary diagnosed error type, or None on any failure."""
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(5.0)) as client:
            response = await client.post(
                f"{settings.AI_SERVICE_URL.rstrip('/')}/internal/diagnose",
                headers={
                    "X-Admin-Api-Key": os.getenv("AI_ADMIN_API_KEY", "").strip()
                },
                json={"text": text, "level": level},
            )
        response.raise_for_status()
        errors = response.json()["errors"]
        return errors[0]["type"] if errors else None
    except Exception:
        logger.warning("Error diagnosis request failed", exc_info=True)
        return None


class AIServiceClient:
    _shared_client: ClassVar[httpx.AsyncClient | None] = None

    def __init__(
        self,
        base_url: Optional[str] = None,
        timeout_seconds: float = 15.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._base_url = (base_url or settings.AI_SERVICE_URL).rstrip("/")
        self._timeout = httpx.Timeout(timeout_seconds)
        self._client = client

    @classmethod
    def start(cls) -> None:
        if cls._shared_client is None or cls._shared_client.is_closed:
            cls._shared_client = httpx.AsyncClient()

    @classmethod
    async def close(cls) -> None:
        if cls._shared_client is not None:
            await cls._shared_client.aclose()
            cls._shared_client = None

    def _http(self) -> httpx.AsyncClient:
        if self._client is not None:
            return self._client
        self.start()
        assert self._shared_client is not None
        return self._shared_client

    async def chat(self, payload: AIChatRequest) -> AIChatResponse:
        """Send a chat request to the AI service.

        The concrete AI service route can evolve; keep this path stable by
        proxying/aliasing on the AI service side when needed.
        """
        url = f"{self._base_url}/chat/respond"

        resp = await self._http().post(
            url,
            json=payload.model_dump(),
            timeout=self._timeout,
        )

        # Prefer raising here; caller can translate to API error envelope.
        resp.raise_for_status()

        data = resp.json() or {}

        # Allow both envelope or direct response from ai-service
        if "data" in data and isinstance(data["data"], dict):
            data = data["data"]

        return AIChatResponse(**data)

    async def translate_word(
        self,
        *,
        word: str,
        lang: str = "vi",
        context: str = "",
        timeout_seconds: float = 8.0,
    ) -> dict:
        """Call ai-service for LLM-powered contextual word translation.

        Never raises — returns empty fields on any failure so the caller
        can still display phonetic/definition from the Free Dictionary.
        """
        url = f"{self._base_url}/ai/translate"
        params: dict = {"word": word, "lang": lang}
        if context:
            params["context"] = context
        api_key = os.getenv("AI_ADMIN_API_KEY", "").strip()
        headers = {"X-Admin-Key": api_key} if api_key else {}

        try:
            resp = await self._http().get(
                url,
                params=params,
                headers=headers,
                timeout=httpx.Timeout(timeout_seconds),
            )
            if resp.status_code == 200:
                return resp.json()
            logger.warning(
                "AI translation returned HTTP %s",
                resp.status_code,
            )
        except Exception as exc:
            logger.warning(
                "AI translation failed (%s)",
                type(exc).__name__,
            )

        return {"translation": "", "phonetic": "", "part_of_speech": ""}

    async def assess_pronunciation(
        self,
        *,
        audio_bytes: bytes,
        filename: str,
        target_text: str,
        authorization: Optional[str] = None,
    ) -> dict[str, Any]:
        """Send audio to the AI service for HuBERT pronunciation assessment."""
        url = f"{self._base_url}/stt/assess-pronunciation"
        headers = {}
        if authorization:
            headers["Authorization"] = authorization

        files = {
            "audio": (
                filename or "recording.wav",
                audio_bytes,
                "audio/wav",
            )
        }
        data = {"target_text": target_text}

        resp = await self._http().post(
            url,
            data=data,
            files=files,
            headers=headers,
            timeout=httpx.Timeout(60.0),
        )

        resp.raise_for_status()
        return resp.json() or {}

    async def transcribe_audio(
        self,
        *,
        audio_bytes: bytes,
        filename: str,
        language: str = "en",
        authorization: Optional[str] = None,
    ) -> dict[str, Any]:
        """Send audio to the AI service for STT transcription."""
        url = f"{self._base_url}/stt/transcribe"
        headers = {}
        if authorization:
            headers["Authorization"] = authorization

        files = {
            "audio": (
                filename or "recording.wav",
                audio_bytes,
                "audio/mpeg",
            )
        }
        data = {"language": language}

        resp = await self._http().post(
            url,
            data=data,
            files=files,
            headers=headers,
            timeout=httpx.Timeout(120.0),
        )

        resp.raise_for_status()
        return resp.json() or {}
