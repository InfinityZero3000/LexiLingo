"""Tests for RankingAgentJobService state machine."""

import uuid
from types import SimpleNamespace

import pytest

from app.services.ranking_agent_jobs import (
    ACTIVE_STATUSES,
    TERMINAL_STATUSES,
    RankingAgentJobService,
)


def _make_job(status: str = "queued") -> SimpleNamespace:
    return SimpleNamespace(
        id=uuid.uuid4(),
        status=status,
        progress={"stage": status, "percent": 0, "counters": {}},
        updated_at=None,
        started_at=None,
        completed_at=None,
        artifact=None,
        warnings=[],
        blocking_errors=[],
        error_message=None,
    )


class FakeDB:
    def __init__(self):
        self.flushed = 0

    async def flush(self):
        self.flushed += 1


@pytest.mark.asyncio
async def test_transition_queued_to_calculating():
    job = _make_job("queued")
    db = FakeDB()
    updated = await RankingAgentJobService.transition(db, job, "calculating", percent=20)
    assert updated.status == "calculating"
    assert updated.progress["percent"] == 20
    assert updated.started_at is not None


@pytest.mark.asyncio
async def test_transition_invalid_raises():
    job = _make_job("completed")
    db = FakeDB()
    with pytest.raises(ValueError, match="Invalid ranking-agent job transition"):
        await RankingAgentJobService.transition(db, job, "calculating")


@pytest.mark.asyncio
async def test_set_preview_moves_to_preview_ready():
    job = _make_job("validating")
    db = FakeDB()
    updated = await RankingAgentJobService.set_preview(
        db,
        job,
        artifact={"total_participants": 10},
        warnings=["minor warning"],
        blocking_errors=[],
    )
    assert updated.status == "preview_ready"
    assert updated.artifact == {"total_participants": 10}
    assert updated.warnings == ["minor warning"]
    assert updated.blocking_errors == []


@pytest.mark.asyncio
async def test_fail_sets_error_message():
    job = _make_job("calculating")
    db = FakeDB()
    updated = await RankingAgentJobService.fail(db, job, "Something went wrong")
    assert updated.status == "failed"
    assert updated.error_message == "Something went wrong"


@pytest.mark.asyncio
async def test_fail_on_terminal_job_is_noop():
    job = _make_job("completed")
    db = FakeDB()
    result = await RankingAgentJobService.fail(db, job, "msg")
    assert result.status == "completed"


@pytest.mark.asyncio
async def test_cancel_terminal_raises():
    job = _make_job("completed")
    db = FakeDB()
    with pytest.raises(ValueError, match="Cannot cancel"):
        await RankingAgentJobService.cancel(db, job)


@pytest.mark.asyncio
async def test_retry_from_failed():
    job = _make_job("failed")
    job.error_message = "old error"
    job.artifact = {"stale": True}
    job.blocking_errors = ["err"]
    job.warnings = ["w"]
    job.completed_at = "something"
    db = FakeDB()
    updated = await RankingAgentJobService.retry(db, job)
    assert updated.status == "queued"
    assert updated.artifact is None
    assert updated.error_message is None
    assert updated.blocking_errors == []


@pytest.mark.asyncio
async def test_retry_from_active_raises():
    job = _make_job("calculating")
    db = FakeDB()
    with pytest.raises(ValueError, match="Cannot retry"):
        await RankingAgentJobService.retry(db, job)


def test_active_and_terminal_status_sets_are_disjoint():
    assert ACTIVE_STATUSES.isdisjoint(TERMINAL_STATUSES)
