"""Tests for the deterministic learner-state evolution algorithm."""

from dataclasses import replace
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from sqlalchemy.dialects import postgresql

from app.services.learner_state import (
    LearnerStateSnapshot,
    ObservationInput,
    TooManyConceptsError,
    _validate_observation,
    apply_observation_event,
    evolve_state,
    get_due_concepts_for_user,
    get_states_for_concepts,
    ingest_observations,
)

NOW = datetime(2026, 7, 12, 12, 0, tzinfo=UTC)


def prior(**overrides) -> LearnerStateSnapshot:
    values = {
        "mastery_probability": 0.5,
        "stability_days": 3.0,
        "difficulty": 0.5,
        "attempt_count": 0,
        "correct_count": 0,
        "error_count": 0,
        "last_interacted_at": NOW - timedelta(days=1),
        "state_version": 1,
    }
    values.update(overrides)
    return LearnerStateSnapshot(**values)


def test_low_confidence_evidence_moves_mastery_less() -> None:
    low = evolve_state(prior(), outcome="incorrect", confidence=0.2, now=NOW)
    high = evolve_state(prior(), outcome="incorrect", confidence=0.9, now=NOW)

    assert abs(low.mastery_probability - 0.5) < abs(high.mastery_probability - 0.5)


@pytest.mark.parametrize("outcome", ["correct", "incorrect"])
def test_mastery_and_scheduler_values_are_bounded(outcome: str) -> None:
    result = evolve_state(
        prior(mastery_probability=0.99, stability_days=0.25),
        outcome=outcome,
        confidence=1.0,
        now=NOW,
    )

    assert 0.01 <= result.mastery_probability <= 0.99
    assert result.stability_days >= 0.25
    assert 0.0 <= result.difficulty <= 1.0
    assert result.next_review_at > NOW


def test_correct_and_incorrect_evidence_update_counts_and_direction() -> None:
    correct = evolve_state(prior(), outcome="correct", confidence=1.0, now=NOW)
    incorrect = evolve_state(prior(), outcome="incorrect", confidence=1.0, now=NOW)

    assert correct.mastery_probability > incorrect.mastery_probability
    assert correct.correct_count == 1 and correct.error_count == 0
    assert incorrect.correct_count == 0 and incorrect.error_count == 1
    assert correct.attempt_count == incorrect.attempt_count == 1
    assert correct.state_version == incorrect.state_version == 2


def test_elapsed_time_decays_mastery_and_result_is_deterministic() -> None:
    recent = evolve_state(prior(last_interacted_at=NOW), "correct", 0.0, NOW)
    stale_prior = prior(last_interacted_at=NOW - timedelta(days=30))
    stale = evolve_state(stale_prior, "correct", 0.0, NOW)

    assert stale.mastery_probability < recent.mastery_probability
    assert stale == evolve_state(stale_prior, "correct", 0.0, NOW)


def test_late_observation_policy_never_regresses_learner_clock() -> None:
    current = prior(last_interacted_at=NOW)
    effective_time = max(NOW - timedelta(days=2), current.last_interacted_at)
    result = evolve_state(current, "incorrect", 0.8, effective_time)

    assert result.last_interacted_at == NOW


@pytest.mark.parametrize(
    ("outcome", "confidence"),
    [("unknown", 0.5), ("correct", -0.1), ("incorrect", 1.1)],
)
def test_invalid_observation_is_rejected(outcome: str, confidence: float) -> None:
    with pytest.raises(ValueError):
        evolve_state(prior(), outcome=outcome, confidence=confidence, now=NOW)


def test_observation_requires_server_contract_event_id_and_bounded_concept() -> None:
    valid = ObservationInput(
        event_id="a" * 64,
        user_id=uuid4(),
        concept_id="concept:grammar.past_simple",
        outcome="incorrect",
        confidence=0.8,
        observed_at=NOW,
    )
    _validate_observation(valid)

    with pytest.raises(ValueError, match="SHA-256"):
        _validate_observation(replace(valid, event_id="client-controlled"))
    with pytest.raises(ValueError, match="1..255"):
        _validate_observation(replace(valid, concept_id="x" * 256))


@pytest.mark.asyncio
async def test_batch_read_rejects_unbounded_input_before_database_access() -> None:
    session = MagicMock()
    session.scalar = AsyncMock()
    session.scalars = AsyncMock()

    with pytest.raises(TooManyConceptsError, match="at most 2"):
        await get_states_for_concepts(
            session,
            uuid4(),
            ["concept:a", "concept:b", "concept:c"],
            limit=2,
        )

    session.scalar.assert_not_awaited()
    session.scalars.assert_not_awaited()


@pytest.mark.asyncio
async def test_batch_read_deduplicates_and_preserves_requested_order() -> None:
    first = SimpleNamespace(concept_id="concept:first")
    second = SimpleNamespace(concept_id="concept:second")
    scalar_rows = MagicMock()
    scalar_rows.all.return_value = [second, first]
    session = MagicMock()
    session.scalar = AsyncMock(return_value=7)
    session.scalars = AsyncMock(return_value=scalar_rows)

    result = await get_states_for_concepts(
        session,
        uuid4(),
        ["concept:first", "concept:second", "concept:first", "concept:missing"],
    )

    assert result.state_epoch == 7
    assert result.states == (first, second)
    session.scalar.assert_awaited_once()
    session.scalars.assert_awaited_once()


@pytest.mark.asyncio
async def test_get_due_concepts_for_user_queries_without_requiring_concept_ids() -> None:
    due_vocab = SimpleNamespace(concept_id="vocab:hotel")
    due_grammar = SimpleNamespace(concept_id="grammar:past_simple")
    scalar_rows = MagicMock()
    scalar_rows.all.return_value = [due_vocab, due_grammar]
    session = MagicMock()
    session.scalars = AsyncMock(return_value=scalar_rows)

    result = await get_due_concepts_for_user(session, uuid4(), now=NOW, limit=10)

    assert result == [due_vocab, due_grammar]
    session.scalars.assert_awaited_once()


@pytest.mark.asyncio
async def test_get_due_concepts_for_user_clamps_limit_to_batch_max() -> None:
    scalar_rows = MagicMock()
    scalar_rows.all.return_value = []
    session = MagicMock()
    session.scalars = AsyncMock(return_value=scalar_rows)

    await get_due_concepts_for_user(session, uuid4(), now=NOW, limit=99999)

    session.scalars.assert_awaited_once()
    executed_statement = session.scalars.await_args.args[0]
    compiled = executed_statement.compile(
        dialect=postgresql.dialect(), compile_kwargs={"literal_binds": True}
    )
    assert "LIMIT 100" in str(compiled)


def observation(**overrides) -> ObservationInput:
    values = {
        "event_id": "a" * 64,
        "user_id": uuid4(),
        "concept_id": "concept:grammar.past_simple",
        "outcome": "correct",
        "confidence": 0.8,
        "observed_at": NOW,
    }
    values.update(overrides)
    return ObservationInput(**values)


@pytest.mark.asyncio
async def test_ingestion_uses_postgresql_idempotency_contract() -> None:
    returned = MagicMock()
    returned.all.return_value = ["a" * 64]
    session = MagicMock()
    session.bind.dialect.name = "postgresql"
    captured = []

    async def execute_scalars(statement):
        captured.append(statement)
        return returned

    session.scalars = AsyncMock(side_effect=execute_scalars)

    inserted = await ingest_observations(session, [observation()])

    assert inserted == {"a" * 64}
    sql = str(
        captured[0].compile(
            dialect=postgresql.dialect(),
            compile_kwargs={"literal_binds": False},
        )
    )
    assert "ON CONFLICT (event_id) DO NOTHING" in sql
    assert "RETURNING learner_observation_events.event_id" in sql
    # The service deliberately leaves commit/rollback ownership to its caller.
    assert not hasattr(session, "commit") or session.commit.call_count == 0


@pytest.mark.asyncio
async def test_ingestion_rejects_oversized_batch_before_database_access() -> None:
    session = MagicMock()
    session.scalars = AsyncMock()

    with pytest.raises(ValueError, match="at most 1"):
        await ingest_observations(
            session,
            [observation(), observation(event_id="b" * 64)],
            limit=1,
        )

    session.scalars.assert_not_awaited()


@pytest.mark.asyncio
async def test_apply_atomically_updates_state_epoch_and_event() -> None:
    user_id = uuid4()
    event = SimpleNamespace(
        user_id=user_id,
        concept_id="concept:grammar.past_simple",
        outcome="correct",
        confidence=0.9,
        observed_at=NOW - timedelta(hours=1),
        status="processing",
        applied_at=None,
        claimed_at=NOW - timedelta(seconds=1),
        last_error_code="transient",
    )
    state = SimpleNamespace(
        mastery_probability=0.5,
        stability_days=3.0,
        difficulty=0.5,
        attempt_count=0,
        correct_count=0,
        error_count=0,
        last_interacted_at=NOW - timedelta(days=1),
        next_review_at=None,
        state_version=1,
        algorithm_version="bkt-fsrs-v1",
        updated_at=NOW - timedelta(days=1),
    )
    profile = SimpleNamespace(state_epoch=11, updated_at=NOW - timedelta(days=1))
    session = MagicMock()
    session.scalar = AsyncMock(side_effect=[event, state, profile])
    session.execute = AsyncMock()
    session.flush = AsyncMock()

    applied = await apply_observation_event(session, uuid4(), now=NOW)

    assert applied is True
    assert state.attempt_count == 1
    assert state.correct_count == 1
    assert state.state_version == 2
    assert state.updated_at == NOW
    assert profile.state_epoch == 12
    assert profile.updated_at == NOW
    assert event.status == "applied"
    assert event.applied_at == NOW
    assert event.claimed_at is None
    assert event.last_error_code is None
    assert session.execute.await_count == 2
    session.flush.assert_awaited_once()


@pytest.mark.asyncio
async def test_apply_is_noop_when_event_was_already_applied() -> None:
    session = MagicMock()
    session.scalar = AsyncMock(return_value=SimpleNamespace(status="applied"))
    session.execute = AsyncMock()
    session.flush = AsyncMock()

    applied = await apply_observation_event(session, uuid4(), now=NOW)

    assert applied is False
    session.execute.assert_not_awaited()
    session.flush.assert_not_awaited()
