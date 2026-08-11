import asyncio
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.models.learner_state import (
    LearnerConceptState,
    LearnerObservationEvent,
    LearnerStateProfile,
)
from app.services.learner_state_outbox import LearnerStateOutboxWorker


def _event(*, event_id: str, user_id, status: str = "pending", claimed_at=None):
    now = datetime.now(UTC)
    return LearnerObservationEvent(
        event_id=event_id,
        user_id=user_id,
        session_id="session-1",
        concept_id="concept:past-tense",
        outcome="correct" if event_id.endswith("1") else "incorrect",
        confidence=0.8,
        observed_at=now,
        payload={"source": "integration"},
        status=status,
        attempt_count=1 if status == "processing" else 0,
        available_at=now - timedelta(seconds=1),
        claimed_at=claimed_at,
    )


@pytest.mark.asyncio
async def test_two_workers_apply_same_concept_events_once_in_deterministic_order(
    db_engine,
    db_session: AsyncSession,
    test_user,
):
    first = _event(event_id="0" * 63 + "1", user_id=test_user.id)
    second = _event(event_id="0" * 63 + "2", user_id=test_user.id)
    user_id = test_user.id
    db_session.add_all([second, first])
    await db_session.commit()

    factory = async_sessionmaker(
        db_engine, class_=AsyncSession, expire_on_commit=False
    )
    workers = [
        LearnerStateOutboxWorker(session_factory=factory, batch_size=10),
        LearnerStateOutboxWorker(session_factory=factory, batch_size=10),
    ]

    first_wave = await asyncio.gather(*(worker.run_once() for worker in workers))
    second_wave = await asyncio.gather(*(worker.run_once() for worker in workers))

    assert sum(first_wave) == 1
    assert sum(second_wave) == 1
    db_session.expire_all()
    events = list(
        (
            await db_session.scalars(
                select(LearnerObservationEvent).order_by(
                    LearnerObservationEvent.event_id
                )
            )
        ).all()
    )
    state = await db_session.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == user_id,
            LearnerConceptState.concept_id == "concept:past-tense",
        )
    )
    profile = await db_session.get(LearnerStateProfile, user_id)
    assert [event.status for event in events] == ["applied", "applied"]
    assert [event.attempt_count for event in events] == [1, 1]
    assert state is not None and state.attempt_count == 2
    assert profile is not None and profile.state_epoch == 2


@pytest.mark.asyncio
async def test_expired_processing_lease_is_reclaimed_and_replayed_once(
    db_engine,
    db_session: AsyncSession,
    test_user,
):
    event = _event(
        event_id="f" * 64,
        user_id=test_user.id,
        status="processing",
        claimed_at=datetime.now(UTC) - timedelta(minutes=2),
    )
    user_id = test_user.id
    db_session.add(event)
    await db_session.commit()
    event_pk = event.id

    factory = async_sessionmaker(
        db_engine, class_=AsyncSession, expire_on_commit=False
    )
    worker = LearnerStateOutboxWorker(
        session_factory=factory, lease_seconds=1, batch_size=10
    )

    assert await worker.run_once() == 1
    assert await worker.run_once() == 0

    db_session.expire_all()
    replayed = await db_session.get(LearnerObservationEvent, event_pk)
    profile = await db_session.get(LearnerStateProfile, user_id)
    assert replayed is not None and replayed.status == "applied"
    assert replayed.attempt_count == 2
    assert replayed.claimed_at is None
    assert profile is not None and profile.state_epoch == 1
