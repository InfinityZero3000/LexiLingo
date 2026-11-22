"""Personalized content recommendations."""

import uuid
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import get_cached, set_cached
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.common import ApiResponse
from app.schemas.recommendation import RecommendationItem, RecommendationResponse
from app.services.recommendation_client import RecommendationClient
from app.services.recommendation_service import (
    attach_mastery,
    build_candidates,
    build_profile,
    get_interaction_epoch,
    get_state_epoch,
)

router = APIRouter(prefix="/recommendations", tags=["Recommendations"])

# Short on purpose: candidates also depend on enrolments, lesson completions and
# due vocab, none of which bump an epoch. The epochs in the key drop the entry
# the moment graded practice, a level change or browsing is recorded.
RESPONSE_CACHE_TTL_SECONDS = 90


def response_cache_key(
    user_id: uuid.UUID, surface: str, limit: int, state_epoch: int, interaction_epoch: int
) -> str:
    return f"rec:resp:v1:{user_id}:{surface}:{limit}:{state_epoch}:{interaction_epoch}"


@router.get("", response_model=ApiResponse[RecommendationResponse])
async def get_recommendations(
    surface: Literal["home", "practice", "vocab", "video"] = Query("home"),
    limit: int = Query(10, ge=1, le=30),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Top-K personalized items, ranked by RecGraph in ai-service."""
    cache_key = response_cache_key(
        current_user.id,
        surface,
        limit,
        await get_state_epoch(db, current_user.id),
        await get_interaction_epoch(current_user.id),
    )
    cached = await get_cached(cache_key)
    if isinstance(cached, dict):
        try:
            hit = RecommendationResponse(**cached)
        except ValueError:
            hit = None
        if hit is not None:
            return ApiResponse(data=hit.model_copy(update={"cache_hit": True}))

    profile = await build_profile(db, current_user.id)
    candidates = await build_candidates(db, current_user.id, profile)
    profile = await attach_mastery(db, current_user.id, profile, candidates)

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
    result = RecommendationResponse(
        items=[
            RecommendationItem(**_shape(item))
            for item in ranked.get("recommendations", [])
        ],
        surface=surface,
        cache_hit=bool(metadata.get("cache_hit")),
        latency_ms=int(metadata.get("latency_ms", 0)),
    )
    await set_cached(
        cache_key, result.model_dump(mode="json"), ttl=RESPONSE_CACHE_TTL_SECONDS
    )
    return ApiResponse(data=result)


def _shape(item: dict) -> dict:
    allowed = RecommendationItem.model_fields.keys()
    return {key: value for key, value in item.items() if key in allowed}
