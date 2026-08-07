"""Private service-to-service learner-state routes."""

import logging
import secrets
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.schemas.learner_state import (
    LearnerConceptStateResponse,
    LearnerObservationBatchRequest,
    LearnerObservationBatchResponse,
    LearnerStateBatchGetRequest,
    LearnerStateBatchGetResponse,
)
from app.services.learner_state import (
    ObservationInput,
    get_states_for_concepts,
    ingest_observations,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/internal/learner-state", tags=["Internal Learner State"])


async def _set_learner_statement_timeout(db: AsyncSession) -> None:
    if db.bind is not None and db.bind.dialect.name == "postgresql":
        timeout_ms = max(10, min(settings.LEARNER_STATE_STATEMENT_TIMEOUT_MS, 5000))
        await db.execute(text(f"SET LOCAL statement_timeout = {timeout_ms}"))


async def require_learner_state_service(
    x_lexilingo_service_token: str = Header(default=""),
    x_lexilingo_audience: str = Header(default=""),
) -> str:
    if not settings.LEARNER_STATE_ENABLED:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    if not secrets.compare_digest(
        x_lexilingo_audience, settings.LEARNER_STATE_INTERNAL_AUDIENCE
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid service identity")
    tokens = [settings.LEARNER_STATE_INTERNAL_TOKEN]
    previous_expiry = settings.LEARNER_STATE_INTERNAL_TOKEN_PREVIOUS_EXPIRES_AT
    if (
        settings.LEARNER_STATE_INTERNAL_TOKEN_PREVIOUS
        and previous_expiry is not None
        and previous_expiry > datetime.now(UTC)
    ):
        tokens.append(settings.LEARNER_STATE_INTERNAL_TOKEN_PREVIOUS)
    if not x_lexilingo_service_token or not any(
        token and secrets.compare_digest(x_lexilingo_service_token, token) for token in tokens
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid service identity")
    return "ai-service"


@router.post("/batch-get", response_model=LearnerStateBatchGetResponse)
async def batch_get_learner_state(
    request: LearnerStateBatchGetRequest,
    _caller: str = Depends(require_learner_state_service),
    db: AsyncSession = Depends(get_db),
) -> LearnerStateBatchGetResponse:
    await _set_learner_statement_timeout(db)
    result = await get_states_for_concepts(db, request.user_id, request.concept_ids)
    return LearnerStateBatchGetResponse(
        state_epoch=result.state_epoch,
        states=[
            LearnerConceptStateResponse.model_validate(row, from_attributes=True)
            for row in result.states
        ],
        goal=result.goal,
        interest=result.interest,
    )


@router.post("/observations:batch", response_model=LearnerObservationBatchResponse)
async def ingest_learner_observation_batch(
    request: LearnerObservationBatchRequest,
    _caller: str = Depends(require_learner_state_service),
    db: AsyncSession = Depends(get_db),
) -> LearnerObservationBatchResponse:
    await _set_learner_statement_timeout(db)
    observations = [
        ObservationInput(
            event_id=item.event_id,
            user_id=item.user_id,
            session_id=item.session_id,
            concept_id=item.concept_id,
            outcome=item.outcome,
            confidence=item.confidence,
            observed_at=item.observed_at,
            payload=item.payload,
        )
        for item in request.observations
    ]
    inserted = await ingest_observations(db, observations)
    await db.commit()  # durability boundary: never ACK an uncommitted outbox row
    requested = {item.event_id for item in observations}
    logger.info(
        "learner observations ingested caller=%s accepted=%d duplicates=%d",
        _caller,
        len(inserted),
        len(requested - inserted),
    )
    return LearnerObservationBatchResponse(
        accepted_event_ids=sorted(inserted),
        duplicate_event_ids=sorted(requested - inserted),
    )
