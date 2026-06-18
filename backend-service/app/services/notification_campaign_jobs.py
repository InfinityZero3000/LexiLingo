"""Application service for Notification Campaign Agent jobs."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification_campaign import NotificationCampaignJob

ACTIVE_STATUSES: frozenset[str] = frozenset(
    {"queued", "segmenting", "generating", "validating", "preview_ready", "sending"}
)
TERMINAL_STATUSES: frozenset[str] = frozenset({"completed", "failed", "cancelled"})

ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    "queued": {"segmenting", "cancelled", "failed"},
    "segmenting": {"generating", "cancelled", "failed"},
    "generating": {"validating", "cancelled", "failed"},
    "validating": {"preview_ready", "cancelled", "failed"},
    "preview_ready": {"sending", "cancelled"},
    "sending": {"completed", "failed"},
    "failed": {"queued"},
    "cancelled": {"queued"},
    "completed": set(),
}


def _utcnow() -> datetime:
    return datetime.now(UTC)


class NotificationCampaignJobService:
    @staticmethod
    async def create(
        db: AsyncSession,
        *,
        requested_by_id: uuid.UUID,
        job_type: str,
        config: dict,
    ) -> NotificationCampaignJob:
        job = NotificationCampaignJob(
            requested_by_id=requested_by_id,
            job_type=job_type,
            config=config,
            progress={"stage": "queued", "percent": 0, "counters": {}},
            delivery_stats={},
        )
        db.add(job)
        await db.flush()
        return job

    @staticmethod
    async def get(
        db: AsyncSession, job_id: uuid.UUID, *, lock: bool = False
    ) -> NotificationCampaignJob | None:
        query = select(NotificationCampaignJob).where(NotificationCampaignJob.id == job_id)
        if lock:
            query = query.with_for_update().execution_options(populate_existing=True)
        return await db.scalar(query)

    @staticmethod
    async def list_jobs(
        db: AsyncSession,
        *,
        limit: int = 50,
        offset: int = 0,
        requested_by_id: uuid.UUID | None = None,
    ) -> list[NotificationCampaignJob]:
        query = (
            select(NotificationCampaignJob)
            .order_by(NotificationCampaignJob.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        if requested_by_id is not None:
            query = query.where(NotificationCampaignJob.requested_by_id == requested_by_id)
        result = await db.execute(query)
        return list(result.scalars().all())

    @staticmethod
    async def count_active_by_requester(
        db: AsyncSession, requester_id: uuid.UUID
    ) -> int:
        result = await db.execute(
            select(func.count(NotificationCampaignJob.id)).where(
                NotificationCampaignJob.requested_by_id == requester_id,
                NotificationCampaignJob.status.in_(ACTIVE_STATUSES),
            )
        )
        return result.scalar_one() or 0

    @staticmethod
    async def transition(
        db: AsyncSession,
        job: NotificationCampaignJob,
        new_status: str,
        *,
        percent: int | None = None,
        stage: str | None = None,
    ) -> None:
        allowed = ALLOWED_TRANSITIONS.get(job.status, set())
        if new_status not in allowed:
            raise ValueError(
                f"Cannot transition notification-campaign job from {job.status!r} to {new_status!r}"
            )
        job.status = new_status
        now = _utcnow()
        progress = dict(job.progress or {})
        if percent is not None:
            progress["percent"] = percent
        if stage is not None:
            progress["stage"] = stage
        else:
            progress["stage"] = new_status
        job.progress = progress
        job.updated_at = now
        if new_status in ("segmenting",) and job.started_at is None:
            job.started_at = now
        if new_status in TERMINAL_STATUSES:
            job.completed_at = now
        await db.flush()

    @staticmethod
    async def set_preview(
        db: AsyncSession,
        job: NotificationCampaignJob,
        *,
        artifact: dict,
        warnings: list[str],
        blocking_errors: list[str],
    ) -> None:
        await NotificationCampaignJobService.transition(db, job, "preview_ready", percent=100)
        job.artifact = artifact
        job.warnings = warnings
        job.blocking_errors = blocking_errors
        await db.flush()

    @staticmethod
    async def set_failed(
        db: AsyncSession,
        job: NotificationCampaignJob,
        error: str,
    ) -> None:
        await NotificationCampaignJobService.transition(db, job, "failed")
        job.error_message = error
        await db.flush()

    @staticmethod
    async def set_delivery_stats(
        db: AsyncSession,
        job: NotificationCampaignJob,
        *,
        sent: int,
        failed: int,
        skipped: int,
    ) -> None:
        job.delivery_stats = {
            "sent": sent,
            "failed": failed,
            "skipped": skipped,
            "total": sent + failed + skipped,
        }
        job.updated_at = _utcnow()
        await db.flush()
