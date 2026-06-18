"""Service-to-service endpoint for Ranking Agent AI insights."""

from __future__ import annotations

import hmac
import logging
import os
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel

from api.core.groq_key_pool import get_groq_key_pool
from api.services.ranking_agent_insights import get_ranking_insights

router = APIRouter(prefix="/api/v1/internal/ranking-agent")
logger = logging.getLogger(__name__)

_admin_key_header = APIKeyHeader(name="X-Admin-Api-Key", auto_error=False)


async def _verify_admin_key(
    provided: str | None = Security(_admin_key_header),
) -> None:
    expected = os.getenv("AI_ADMIN_API_KEY", "").strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI_ADMIN_API_KEY is not configured",
        )
    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin API key",
        )


_JobType = Literal["league_reset", "xp_event", "achievement_batch"]


class InsightsRequest(BaseModel):
    job_type: _JobType
    artifact: dict[str, Any]


class InsightsResponse(BaseModel):
    insight: str | None
    skipped: bool = False


@router.post(
    "/insights",
    response_model=InsightsResponse,
    dependencies=[Security(_verify_admin_key)],
)
async def generate_insights(body: InsightsRequest) -> InsightsResponse:
    """Generate a Groq-powered insight string for a ranking agent preview artifact."""
    insight = await get_ranking_insights(
        job_type=body.job_type,
        artifact=body.artifact,
        groq_pool=get_groq_key_pool(),
    )
    return InsightsResponse(insight=insight, skipped=insight is None)
