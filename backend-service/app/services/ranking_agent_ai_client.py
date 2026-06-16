"""HTTP client for Ranking Agent AI insights via ai-service."""

from __future__ import annotations

import logging
import os
from typing import Any, Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class RankingAgentAIClient:
    def __init__(self) -> None:
        self._base_url = settings.AI_SERVICE_URL.rstrip("/")
        self._api_key = os.getenv("AI_ADMIN_API_KEY", "").strip()
        self._timeout = httpx.Timeout(settings.RANKING_AGENT_AI_INSIGHTS_TIMEOUT_SECONDS)

    async def get_insights(
        self, job_type: str, artifact: dict[str, Any]
    ) -> Optional[str]:
        """
        Call ai-service for Groq-generated insights.
        Returns None on any error so the caller degrades gracefully.
        """
        if not self._api_key:
            logger.warning("AI_ADMIN_API_KEY not set — skipping AI insights")
            return None
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(
                    f"{self._base_url}/internal/ranking-agent/insights",
                    headers={"X-Admin-Api-Key": self._api_key},
                    json={"job_type": job_type, "artifact": artifact},
                )
            if response.status_code != 200:
                logger.warning(
                    "ranking_agent_ai_client: ai-service returned %d",
                    response.status_code,
                )
                return None
            data = response.json()
            return data.get("insight")
        except Exception:
            logger.exception("ranking_agent_ai_client: request to ai-service failed")
            return None
