"""Security and validation contracts for internal learner-state routes."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.core.config import settings
from app.routes import learner_state as learner_state_routes
from app.routes.learner_state import require_learner_state_service
from app.schemas.learner_state import (
    MAX_PAYLOAD_BYTES,
    LearnerObservationBatchRequest,
    LearnerObservationRequest,
    LearnerStateBatchGetRequest,
)


@pytest.mark.asyncio
async def test_internal_auth_accepts_current_and_previous_rotating_tokens(monkeypatch) -> None:
    monkeypatch.setattr(settings, "LEARNER_STATE_ENABLED", True)
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN", "current-secret")
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN_PREVIOUS", "previous-secret")
    monkeypatch.setattr(
        settings,
        "LEARNER_STATE_INTERNAL_TOKEN_PREVIOUS_EXPIRES_AT",
        datetime.now(UTC) + timedelta(hours=1),
    )
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_AUDIENCE", "lexilingo-backend")

    assert await require_learner_state_service("current-secret", "lexilingo-backend") == "ai-service"
    assert await require_learner_state_service("previous-secret", "lexilingo-backend") == "ai-service"


@pytest.mark.asyncio
async def test_internal_auth_hides_disabled_route_and_rejects_wrong_identity(monkeypatch) -> None:
    monkeypatch.setattr(settings, "LEARNER_STATE_ENABLED", False)
    with pytest.raises(HTTPException) as disabled:
        await require_learner_state_service("token", "lexilingo-backend")
    assert disabled.value.status_code == 404

    monkeypatch.setattr(settings, "LEARNER_STATE_ENABLED", True)
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN", "token")
    with pytest.raises(HTTPException) as rejected:
        await require_learner_state_service("wrong", "wrong-audience")
    assert rejected.value.status_code == 401
    assert rejected.value.detail == "invalid service identity"


@pytest.mark.asyncio
async def test_internal_auth_rejects_missing_token_even_with_valid_audience(monkeypatch) -> None:
    monkeypatch.setattr(settings, "LEARNER_STATE_ENABLED", True)
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN", "current-secret")
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_TOKEN_PREVIOUS", "previous-secret")
    monkeypatch.setattr(settings, "LEARNER_STATE_INTERNAL_AUDIENCE", "lexilingo-backend")

    with pytest.raises(HTTPException) as rejected:
        await require_learner_state_service("", "lexilingo-backend")

    assert rejected.value.status_code == 401
    assert rejected.value.detail == "invalid service identity"


def test_batch_contract_deduplicates_and_bounds_concept_ids() -> None:
    request = LearnerStateBatchGetRequest(
        user_id=uuid4(), concept_ids=["concept:a", "concept:a", "concept:b"]
    )
    assert request.concept_ids == ["concept:a", "concept:b"]

    with pytest.raises(ValidationError):
        LearnerStateBatchGetRequest(user_id=uuid4(), concept_ids=[f"c:{i}" for i in range(101)])


def test_observation_rejects_future_clock_skew_and_oversized_payload() -> None:
    base = {
        "event_id": "a" * 64,
        "user_id": uuid4(),
        "concept_id": "concept:a",
        "outcome": "correct",
        "confidence": 0.8,
    }
    with pytest.raises(ValidationError, match="too far in the future"):
        LearnerObservationRequest(
            **base, observed_at=datetime.now(UTC) + timedelta(minutes=6)
        )
    with pytest.raises(ValidationError, match="payload exceeds"):
        LearnerObservationRequest(
            **base,
            observed_at=datetime.now(UTC),
            payload={"text": "x" * (MAX_PAYLOAD_BYTES + 1)},
        )


def _observation(event_id: str) -> LearnerObservationRequest:
    return LearnerObservationRequest(
        event_id=event_id,
        user_id=uuid4(),
        concept_id="concept:a",
        outcome="correct",
        confidence=0.8,
        observed_at=datetime.now(UTC),
    )


def test_observation_batch_is_bounded() -> None:
    with pytest.raises(ValidationError):
        LearnerObservationBatchRequest(
            observations=[_observation(f"{index:064x}") for index in range(101)]
        )


@pytest.mark.asyncio
async def test_batch_get_adapts_repository_result_to_wire_response(monkeypatch) -> None:
    user_id = uuid4()
    state = SimpleNamespace(
        concept_id="concept:a",
        mastery_probability=0.75,
        stability_days=3.0,
        difficulty=0.4,
        attempt_count=4,
        correct_count=3,
        error_count=1,
        last_interacted_at=None,
        next_review_at=None,
        state_version=2,
        algorithm_version="bkt-fsrs-v1",
    )
    repository = AsyncMock(return_value=SimpleNamespace(state_epoch=7, states=[state]))
    monkeypatch.setattr(learner_state_routes, "get_states_for_concepts", repository)

    response = await learner_state_routes.batch_get_learner_state(
        LearnerStateBatchGetRequest(
            user_id=user_id, concept_ids=["concept:a", "concept:a"]
        ),
        _caller="ai-service",
        db=AsyncMock(),
    )

    repository.assert_awaited_once_with(repository.call_args.args[0], user_id, ["concept:a"])
    assert response.state_epoch == 7
    assert [item.concept_id for item in response.states] == ["concept:a"]


@pytest.mark.asyncio
async def test_observation_ingestion_commits_before_ack_and_reports_duplicates(monkeypatch) -> None:
    first = "1" * 64
    duplicate = "2" * 64
    events: list[str] = []

    async def ingest(_db, observations):
        events.append("ingest")
        assert {item.event_id for item in observations} == {first, duplicate}
        return {first}

    db = AsyncMock()

    async def commit():
        events.append("commit")

    db.commit.side_effect = commit
    monkeypatch.setattr(learner_state_routes, "ingest_observations", ingest)
    request = LearnerObservationBatchRequest(
        observations=[_observation(first), _observation(duplicate)]
    )

    response = await learner_state_routes.ingest_learner_observation_batch(
        request, _caller="ai-service", db=db
    )
    events.append("ack")

    assert events == ["ingest", "commit", "ack"]
    assert response.accepted_event_ids == [first]
    assert response.duplicate_event_ids == [duplicate]


@pytest.mark.asyncio
async def test_statement_timeout_is_bounded_and_set_locally(monkeypatch) -> None:
    bind = SimpleNamespace(dialect=SimpleNamespace(name="postgresql"))
    db = AsyncMock()
    db.bind = bind
    monkeypatch.setattr(settings, "LEARNER_STATE_STATEMENT_TIMEOUT_MS", 99_999)

    await learner_state_routes._set_learner_statement_timeout(db)

    statement = db.execute.await_args.args[0]
    assert str(statement) == "SET LOCAL statement_timeout = 5000"
