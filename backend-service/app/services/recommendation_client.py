"""HTTP client for RecGraph ranking in ai-service."""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

_TIMEOUT_SECONDS = 8.0


class RecommendationClient:
    def __init__(self) -> None:
        self._base_url = settings.AI_SERVICE_URL.rstrip("/")
        self._api_key = os.getenv("AI_ADMIN_API_KEY", "").strip()

    async def rank(
        self,
        *,
        user_id: str,
        surface: str,
        k: int,
        profile: dict[str, Any],
        candidates: list[dict[str, Any]],
    ) -> dict[str, Any] | None:
        """Returns None on any failure so the caller can fall back locally."""
        if not self._api_key:
            logger.warning("AI_ADMIN_API_KEY not set — recommendations degrade")
            return None
        try:
            async with httpx.AsyncClient(timeout=_TIMEOUT_SECONDS) as client:
                response = await client.post(
                    f"{self._base_url}/internal/recommendations/rank",
                    headers={"X-Admin-Api-Key": self._api_key},
                    json={
                        "user_id": user_id,
                        "surface": surface,
                        "k": k,
                        "profile": profile,
                        "candidates": candidates,
                    },
                )
            if response.status_code != 200:
                logger.warning(
                    "recommendation_client: ai-service returned %d",
                    response.status_code,
                )
                return None
            return response.json()
        except Exception as exc:
            logger.warning("recommendation_client: %s", exc)
            return None
