"""Integration test: lesson exercises with concept_id feed learner_concept_state."""

from datetime import UTC, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.learner_state import LearnerConceptState, LearnerObservationEvent
from app.routes.learning import _emit_concept_observation


@pytest.mark.asyncio
async def test_emit_concept_observation_creates_learner_concept_state(
    db_session: AsyncSession, test_user
):
    await _emit_concept_observation(
        db_session,
        user_id=test_user.id,
        concept_id="grammar:past_simple",
        is_correct=True,
    )
    await db_session.commit()

    state = await db_session.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == test_user.id,
            LearnerConceptState.concept_id == "grammar:past_simple",
        )
    )
    assert state is not None
    assert state.attempt_count == 1
    assert state.correct_count == 1

    event = await db_session.scalar(
        select(LearnerObservationEvent).where(
            LearnerObservationEvent.user_id == test_user.id,
            LearnerObservationEvent.concept_id == "grammar:past_simple",
        )
    )
    assert event is not None
    assert event.status == "applied"


@pytest.mark.asyncio
async def test_emit_concept_observation_accumulates_across_calls(
    db_session: AsyncSession, test_user
):
    await _emit_concept_observation(
        db_session, user_id=test_user.id, concept_id="grammar:present_perfect", is_correct=False
    )
    await db_session.commit()
    await _emit_concept_observation(
        db_session, user_id=test_user.id, concept_id="grammar:present_perfect", is_correct=True
    )
    await db_session.commit()

    states = (
        await db_session.scalars(
            select(LearnerConceptState).where(
                LearnerConceptState.user_id == test_user.id,
                LearnerConceptState.concept_id == "grammar:present_perfect",
            )
        )
    ).all()
    assert len(states) == 1
    assert states[0].attempt_count == 2
    assert states[0].correct_count == 1
    assert states[0].error_count == 1


@pytest.mark.asyncio
async def test_emit_concept_observation_swallows_failure_without_aborting_session(
    db_session: AsyncSession, test_user, monkeypatch
):
    async def _boom(*args, **kwargs):
        raise RuntimeError("simulated failure")

    import app.routes.learning as learning_module

    monkeypatch.setattr(learning_module, "ingest_observations", _boom)

    # Must not raise, and the session must stay usable afterward (savepoint
    # isolation) — proven by successfully committing unrelated work next.
    await _emit_concept_observation(
        db_session, user_id=test_user.id, concept_id="grammar:broken", is_correct=True
    )
    test_user.display_name = "still usable after failure"
    await db_session.commit()

    state = await db_session.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == test_user.id,
            LearnerConceptState.concept_id == "grammar:broken",
        )
    )
    assert state is None
