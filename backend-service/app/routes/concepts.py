"""User-facing endpoint for the unified spaced-repetition review queue.

Surfaces learner_concept_state (app/services/learner_state.py) directly to
the app — the same BKT+FSRS engine vocabulary review writes through
(app/crud/vocabulary.py submit_review) and lesson exercises feed via
concept_id (app/routes/learning.py _emit_concept_observation). This is the
"one place to see everything due" endpoint: vocabulary AND grammar/mission
concepts together, ordered by how overdue they are.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.response import ApiResponse
from app.services.learner_state import get_due_concepts_for_user

router = APIRouter(tags=["Concepts"])


class DueConceptItem(BaseModel):
    concept_id: str
    concept_type: str
    display_label: str
    mastery_probability: float
    next_review_at: datetime | None


class DueConceptsResponse(BaseModel):
    items: list[DueConceptItem]
    total_due: int


def _describe_concept(concept_id: str) -> tuple[str, str]:
    """Split 'vocab:hotel_room' into ('vocab', 'Hotel Room').

    Deliberately lightweight — no join back to VocabularyItem/Lesson for a
    richer label. Good enough to render a due-review list; a nicer label
    (real word casing, lesson title) can be added later without changing
    this endpoint's contract.
    """
    concept_type, _, remainder = concept_id.partition(":")
    label = remainder.replace("_", " ").strip().title() or concept_id
    return (concept_type or "unknown"), label


@router.get("/due", response_model=ApiResponse[DueConceptsResponse])
async def get_due_concepts(
    limit: int = Query(50, ge=1, le=100, description="Max concepts to review"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Get all concepts (vocabulary, grammar, mission) due for review, ordered
    by how overdue they are. Unifies what used to be vocabulary-only
    (`GET /vocabulary/due`) with grammar/mission mastery tracking.
    """
    now = datetime.now(timezone.utc)
    states = await get_due_concepts_for_user(db, current_user.id, now=now, limit=limit)

    items = []
    for state in states:
        concept_type, label = _describe_concept(state.concept_id)
        items.append(
            DueConceptItem(
                concept_id=state.concept_id,
                concept_type=concept_type,
                display_label=label,
                mastery_probability=state.mastery_probability,
                next_review_at=state.next_review_at,
            )
        )

    return ApiResponse(
        data=DueConceptsResponse(items=items, total_due=len(items))
    )
