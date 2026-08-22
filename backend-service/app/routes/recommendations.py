"""Personalized content recommendations."""

from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.common import ApiResponse
from app.schemas.recommendation import RecommendationItem, RecommendationResponse
from app.services.recommendation_client import RecommendationClient
from app.services.recommendation_service import build_candidates, build_profile

router = APIRouter(prefix="/recommendations", tags=["Recommendations"])


@router.get("", response_model=ApiResponse[RecommendationResponse])
async def get_recommendations(
    surface: Literal["home", "practice", "vocab", "video"] = Query("home"),
    limit: int = Query(10, ge=1, le=30),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Top-K personalized items, ranked by RecGraph in ai-service."""
    profile = await build_profile(db, current_user.id)
    candidates = await build_candidates(db, current_user.id, profile)

    ranked = await RecommendationClient().rank(
        user_id=str(current_user.id),
        surface=surface,
        k=limit,
        profile=profile,
        candidates=candidates,
    )

    if ranked is None:
        # ponytail: no second scorer here on purpose — a fallback ranking is a
        # copy of the score layer that will drift from it. Candidates already
        # arrive due-review-first, which is the single most useful ordering.
        return ApiResponse(
            data=RecommendationResponse(
                items=[RecommendationItem(**_shape(item)) for item in candidates[:limit]],
                surface=surface,
                degraded=True,
            )
        )

    metadata = ranked.get("metadata") or {}
    return ApiResponse(
        data=RecommendationResponse(
            items=[
                RecommendationItem(**_shape(item))
                for item in ranked.get("recommendations", [])
            ],
            surface=surface,
            cache_hit=bool(metadata.get("cache_hit")),
            latency_ms=int(metadata.get("latency_ms", 0)),
        )
    )


def _shape(item: dict) -> dict:
    allowed = RecommendationItem.model_fields.keys()
    return {key: value for key, value in item.items() if key in allowed}
