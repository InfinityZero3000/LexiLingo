"""Service-to-service endpoint for Notification Campaign Agent content generation."""

from __future__ import annotations

import hmac
import logging
import os
from typing import Any

from fastapi import APIRouter, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field

from api.services.notification_agent.graph import get_notification_agent_pipeline

router = APIRouter(prefix="/api/notification-agent")
logger = logging.getLogger(__name__)

_admin_key_header = APIKeyHeader(name="X-Admin-Api-Key", auto_error=False)


async def _verify_admin_key(
    provided: str | None = Security(_admin_key_header),
) -> None:
    expected = os.getenv("AI_ADMIN_API_KEY", "").strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="AI_ADMIN_API_KEY is not configured on this service",
        )
    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin API key",
        )


class GenerateContentRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    body: str = Field(..., min_length=1, max_length=300)
    notification_type: str = Field("campaign", max_length=50)
    audience_profile: dict[str, Any] = Field(default_factory=dict)


class NotificationVariantOut(BaseModel):
    title: str
    body: str
    rationale: str = ""


class GenerateContentResponse(BaseModel):
    best_variant: NotificationVariantOut
    all_variants: list[NotificationVariantOut]
    score: float
    retries: int
    generation_skipped: bool


@router.post(
    "/generate-content",
    response_model=GenerateContentResponse,
    dependencies=[Security(_verify_admin_key)],
)
async def generate_notification_content(
    body: GenerateContentRequest,
) -> GenerateContentResponse:
    """Run the LangGraph notification pipeline to generate personalized push copy."""
    pipeline = get_notification_agent_pipeline()

    try:
        result = await pipeline.run(
            title=body.title,
            body=body.body,
            notification_type=body.notification_type,
            audience_profile=body.audience_profile,
        )
    except Exception as exc:
        logger.exception("Notification agent pipeline failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))

    # pipeline.run() returns final_title/final_body (already quality-gated by finalize_node)
    best = NotificationVariantOut(
        title=result.get("title", body.title),
        body=result.get("body", body.body),
        rationale="",
    )

    return GenerateContentResponse(
        best_variant=best,
        all_variants=[NotificationVariantOut(**v) for v in result.get("variants", [])],
        score=result.get("score", 0.0),
        retries=result.get("retries", 0),
        generation_skipped=result.get("generation_skipped", False),
    )
