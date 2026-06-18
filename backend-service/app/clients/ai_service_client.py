"""AI service client.

Purpose:
- Keep AI integration behind a small client boundary.
- Allow the backend-service to call ai-service later without refactoring routes.

This module is safe to include even when AI is not enabled.
"""

from __future__ import annotations

from typing import Any, Optional

import httpx

from app.core.config import settings
from app.schemas.ai import AIChatRequest, AIChatResponse


class AIServiceClient:
    def __init__(
        self,
        base_url: Optional[str] = None,
        timeout_seconds: float = 15.0,
    ) -> None:
        self._base_url = (base_url or settings.AI_SERVICE_URL).rstrip("/")
        self._timeout = httpx.Timeout(timeout_seconds)

    async def chat(self, payload: AIChatRequest) -> AIChatResponse:
        """Send a chat request to the AI service.

        The concrete AI service route can evolve; keep this path stable by
        proxying/aliasing on the AI service side when needed.
        """
        url = f"{self._base_url}/chat/respond"

        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(url, json=payload.model_dump())

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

        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(timeout_seconds)) as client:
                resp = await client.get(url, params=params)
            if resp.status_code == 200:
                return resp.json()
        except Exception:
            pass

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

        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0)) as client:
            resp = await client.post(url, data=data, files=files, headers=headers)

        resp.raise_for_status()
        return resp.json() or {}
