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


async def invalidate_learner_card(user_id: Any) -> None:
    """Drop ai-service's cached learner card after we changed what it says.

    Fire-and-forget: the card also carries a short TTL, so a lost call costs a
    couple of minutes of staleness, never a failed promotion or enrolment.
    Callers must not await this in a way that can fail their own request.

    ponytail: awaited inline with a 1s ceiling rather than handed to
    BackgroundTasks, which would mean threading a parameter through four
    endpoints. Normally an intra-cluster Redis delete of a few ms — but
    ai-service cold starts are a known slow path here, so the ceiling is what
    the learner actually waits in the worst case. Move it to BackgroundTasks
    if that second ever shows up in enrolment latency.
    """
    api_key = os.getenv("AI_ADMIN_API_KEY", "").strip()
    if not api_key:
        return
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(1.0)) as client:
            response = await client.post(
                f"{settings.AI_SERVICE_URL.rstrip('/')}/internal/learner-card/invalidate",
                headers={"X-Admin-Api-Key": api_key},
                json={"user_id": str(user_id)},
            )
        response.raise_for_status()
    except Exception as exc:
        logger.warning("Learner-card invalidation failed for %s: %s", user_id, exc)


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


async def grade_ielts_submission(
    *,
    skill: str,
    part_key: str,
    task_prompt: str,
    answer_text: str,
    test_type: str = "academic",
) -> dict | None:
    """Grade one IELTS Writing task or Speaking part. None on any failure.

    Returning None rather than a default band is deliberate: an ungraded task
    must stay visibly ungraded so it can be retried, because a band nobody
    computed would flow straight into the reported overall score.
    """
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(90.0)) as client:
            response = await client.post(
                f"{settings.AI_SERVICE_URL.rstrip('/')}/internal/ielts/grade",
                headers={
                    "X-Admin-Api-Key": os.getenv("AI_ADMIN_API_KEY", "").strip()
                },
                json={
                    "skill": skill,
                    "part_key": part_key,
                    "task_prompt": task_prompt,
                    "answer_text": answer_text,
                    "test_type": test_type,
                },
            )
        response.raise_for_status()
        return response.json()
    except Exception:
        logger.warning("IELTS grading request failed", exc_info=True)
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
