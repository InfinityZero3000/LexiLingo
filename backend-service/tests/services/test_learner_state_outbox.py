from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock

import pytest
from sqlalchemy.dialects import postgresql

from app.services import learner_state_outbox as outbox_module
from app.services.learner_state_outbox import (
    LearnerStateOutboxWorker,
    build_claim_statement,
    retry_delay_seconds,
)

NOW = datetime(2026, 7, 13, tzinfo=UTC)


def test_claim_statement_uses_skip_locked_lease_and_deterministic_order():
    statement = build_claim_statement(
        now=NOW, lease_timeout=timedelta(seconds=30), batch_size=100
    )
    sql = str(statement.compile(dialect=postgresql.dialect())).upper()

    assert "FOR UPDATE SKIP LOCKED" in sql
    assert "ORDER BY" in sql
    assert "USER_ID" in sql
    assert "CONCEPT_ID" in sql
    assert "OBSERVED_AT" in sql
    assert "EVENT_ID" in sql
    assert "CLAIMED_AT" in sql
    assert "RETURNING" in sql


def test_retry_backoff_is_bounded_and_deterministic_without_jitter():
    assert retry_delay_seconds(1, jitter=0) == 1
    assert retry_delay_seconds(4, jitter=0) == 8
    assert retry_delay_seconds(100, maximum=30, jitter=0) == 30


class _SessionContext:
    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        return self.session

    async def __aexit__(self, *args):
        return None


@pytest.mark.asyncio
async def test_failed_event_is_retried_with_lease_released(monkeypatch):
    event = MagicMock(status="processing", attempt_count=2)
    session = MagicMock()
    session.scalar = AsyncMock(return_value=event)
    session.commit = AsyncMock()
    worker = LearnerStateOutboxWorker(session_factory=lambda: _SessionContext(session))
    monkeypatch.setattr(outbox_module, "retry_delay_seconds", lambda attempt: 4)

    await worker._mark_failed("event-1", RuntimeError("transient"))

    assert event.status == "retry"
    assert event.claimed_at is None
    assert event.last_error_code == "RuntimeError"
    assert event.available_at > NOW
    session.commit.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_failed_event_becomes_dead_at_attempt_limit():
    event = MagicMock(status="processing", attempt_count=3)
    session = MagicMock()
    session.scalar = AsyncMock(return_value=event)
    session.commit = AsyncMock()
    worker = LearnerStateOutboxWorker(
        session_factory=lambda: _SessionContext(session), max_attempts=3
    )

    await worker._mark_failed("event-1", ValueError("permanent"))

    assert event.status == "dead"
    assert event.claimed_at is None
    assert event.last_error_code == "ValueError"
    session.commit.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_outbox_worker_lifecycle_start_and_stop_is_idempotent():
    worker = LearnerStateOutboxWorker(poll_seconds=0.01)
    worker.run_once = AsyncMock(return_value=0)

    worker.start()
    first_task = worker._task
    worker.start()
    assert worker._task is first_task

    await worker.stop(timeout_seconds=0.2)
    await worker.stop(timeout_seconds=0.2)
    assert worker._task is None


def test_claim_blocks_later_unapplied_event_for_same_user_concept():
    statement = build_claim_statement(
        now=NOW, lease_timeout=timedelta(seconds=30), batch_size=100
    )
    sql = str(statement.compile(dialect=postgresql.dialect())).upper()

    assert "NOT (EXISTS" in sql
    assert "STATUS IN" in sql
    assert "EVENT_ID <" in sql


@pytest.mark.asyncio
async def test_claim_sorts_returned_rows_deterministically():
    rows = [
        ("id-2", "user-b", "c", "e2", NOW),
        ("id-1", "user-a", "z", "e3", NOW),
        ("id-3", "user-a", "a", "e1", NOW),
    ]
    result = MagicMock()
    result.all.return_value = rows
    session = MagicMock()
    session.execute = AsyncMock(return_value=result)
    session.commit = AsyncMock()
    worker = LearnerStateOutboxWorker(session_factory=lambda: _SessionContext(session))

    claimed = await worker.claim()

    assert [item.id for item in claimed] == ["id-3", "id-1", "id-2"]
