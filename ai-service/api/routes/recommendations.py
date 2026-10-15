"""Internal ranking endpoint for the recommender.

backend-service owns the data (catalog, learner state, events) and supplies the
candidate pool; ai-service owns the model (embeddings) and the graph. Splitting
it this way keeps ai-service free of a PostgreSQL dependency it does not have.
"""

import hmac
import os

from fastapi import APIRouter, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field

from api.services.rec_graph.graph import get_rec_graph

router = APIRouter(prefix="/api/v1/internal/recommendations")

_admin_key_header = APIKeyHeader(name="X-Admin-Api-Key", auto_error=False)


async def _verify_admin_key(provided: str | None = Security(_admin_key_header)) -> None:
    expected = os.getenv("AI_ADMIN_API_KEY", "").strip()
    if not expected:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "AI_ADMIN_API_KEY is not configured"
        )
    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid admin API key")


class Candidate(BaseModel):
    item_id: str
    item_type: str
    title: str = ""
    description: str = ""
    topic: str | None = None
    level: str | None = None
    skill: str | None = None
    tags: list[str] = Field(default_factory=list)
    concept_ids: list[str] = Field(default_factory=list)
    seen_hours_ago: float | None = None
    sequential: float = 0.0
    payload: dict = Field(default_factory=dict)


class RankRequest(BaseModel):
    user_id: str
    surface: str = "home"
    k: int = Field(default=10, ge=1, le=50)
    profile: dict = Field(default_factory=dict)
    candidates: list[Candidate] = Field(default_factory=list)


@router.post("/rank", dependencies=[Security(_verify_admin_key)])
async def rank(body: RankRequest) -> dict:
    pipeline = await get_rec_graph()
    return await pipeline.recommend(
        user_id=body.user_id,
        profile=body.profile,
        candidates=[c.model_dump() for c in body.candidates],
        surface=body.surface,
        k=body.k,
    )
