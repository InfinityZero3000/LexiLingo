"""State machine tests for NotificationCampaignJobService."""

from __future__ import annotations

import uuid
from types import SimpleNamespace

import pytest

from app.services.notification_campaign_jobs import (
    ACTIVE_STATUSES,
    ALLOWED_TRANSITIONS,
    TERMINAL_STATUSES,
    NotificationCampaignJobService,
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
        delivery_stats={},
    )


class FakeDB:
    def __init__(self) -> None:
        self.flushed: int = 0

    async def flush(self) -> None:
        self.flushed += 1


# ---------------------------------------------------------------------------
# Status set invariants
# ---------------------------------------------------------------------------


def test_active_and_terminal_statuses_are_disjoint() -> None:
    assert ACTIVE_STATUSES.isdisjoint(TERMINAL_STATUSES)


def test_all_allowed_transition_sources_covered() -> None:
    all_statuses = ACTIVE_STATUSES | TERMINAL_STATUSES
    for source in ALLOWED_TRANSITIONS:
        assert source in all_statuses, f"{source!r} not in known statuses"


# ---------------------------------------------------------------------------
# transition() — valid moves
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_transition_queued_to_segmenting() -> None:
    job = _make_job("queued")
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "segmenting", percent=10)
    assert job.status == "segmenting"
    assert job.progress["percent"] == 10
    assert job.started_at is not None


@pytest.mark.asyncio
async def test_transition_segmenting_to_generating() -> None:
    job = _make_job("segmenting")
    job.started_at = "set"
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "generating", percent=30)
    assert job.status == "generating"


@pytest.mark.asyncio
async def test_transition_generating_to_validating() -> None:
    job = _make_job("generating")
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "validating", percent=60)
    assert job.status == "validating"


@pytest.mark.asyncio
async def test_transition_validating_to_preview_ready() -> None:
    job = _make_job("validating")
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "preview_ready", percent=100)
    assert job.status == "preview_ready"


@pytest.mark.asyncio
async def test_transition_preview_ready_to_sending() -> None:
    job = _make_job("preview_ready")
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "sending", percent=0)
    assert job.status == "sending"


@pytest.mark.asyncio
async def test_transition_sending_to_completed_sets_completed_at() -> None:
    job = _make_job("sending")
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "completed")
    assert job.status == "completed"
    assert job.completed_at is not None


# ---------------------------------------------------------------------------
# transition() — invalid moves
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_transition_completed_to_calculating_raises() -> None:
    job = _make_job("completed")
    db = FakeDB()
    with pytest.raises(ValueError, match="Cannot transition"):
        await NotificationCampaignJobService.transition(db, job, "segmenting")


@pytest.mark.asyncio
async def test_transition_queued_to_completed_directly_raises() -> None:
    job = _make_job("queued")
    db = FakeDB()
    with pytest.raises(ValueError, match="Cannot transition"):
        await NotificationCampaignJobService.transition(db, job, "completed")


# ---------------------------------------------------------------------------
# set_preview()
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_set_preview_stores_artifact_and_moves_to_preview_ready() -> None:
    job = _make_job("validating")
    db = FakeDB()
    await NotificationCampaignJobService.set_preview(
        db,
        job,
        artifact={"audience_size": 42, "sample_users": []},
        warnings=["low audience"],
        blocking_errors=[],
    )
    assert job.status == "preview_ready"
    assert job.artifact == {"audience_size": 42, "sample_users": []}
    assert job.warnings == ["low audience"]
    assert job.blocking_errors == []


@pytest.mark.asyncio
async def test_set_preview_stores_blocking_errors() -> None:
    job = _make_job("validating")
    db = FakeDB()
    await NotificationCampaignJobService.set_preview(
        db,
        job,
        artifact={},
        warnings=[],
        blocking_errors=["no FCM tokens"],
    )
    assert job.blocking_errors == ["no FCM tokens"]


# ---------------------------------------------------------------------------
# set_failed()
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_set_failed_from_segmenting() -> None:
    job = _make_job("segmenting")
    db = FakeDB()
    await NotificationCampaignJobService.set_failed(db, job, "DB timeout")
    assert job.status == "failed"
    assert job.error_message == "DB timeout"
    assert job.completed_at is not None


@pytest.mark.asyncio
async def test_set_failed_from_sending() -> None:
    job = _make_job("sending")
    db = FakeDB()
    await NotificationCampaignJobService.set_failed(db, job, "FCM unreachable")
    assert job.status == "failed"


# ---------------------------------------------------------------------------
# cancel via transition()
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cancel_from_queued() -> None:
    job = _make_job("queued")
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "cancelled")
    assert job.status == "cancelled"
    assert job.completed_at is not None


@pytest.mark.asyncio
async def test_cancel_from_completed_raises() -> None:
    job = _make_job("completed")
    db = FakeDB()
    with pytest.raises(ValueError, match="Cannot transition"):
        await NotificationCampaignJobService.transition(db, job, "cancelled")


# ---------------------------------------------------------------------------
# retry — failed → queued
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_retry_from_failed_to_queued() -> None:
    job = _make_job("failed")
    db = FakeDB()
    await NotificationCampaignJobService.transition(db, job, "queued")
    assert job.status == "queued"


# ---------------------------------------------------------------------------
# set_delivery_stats()
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_set_delivery_stats_stores_values() -> None:
    job = _make_job("sending")
    db = FakeDB()
    await NotificationCampaignJobService.set_delivery_stats(
        db, job, sent=100, failed=3, skipped=7
    )
    assert job.delivery_stats["sent"] == 100
    assert job.delivery_stats["failed"] == 3
    assert job.delivery_stats["skipped"] == 7
    assert job.delivery_stats["total"] == 110


@pytest.mark.asyncio
async def test_set_delivery_stats_zero_is_valid() -> None:
    job = _make_job("sending")
    db = FakeDB()
    await NotificationCampaignJobService.set_delivery_stats(
        db, job, sent=0, failed=0, skipped=0
    )
    assert job.delivery_stats["total"] == 0
