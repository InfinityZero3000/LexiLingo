"""Application service for durable Ranking/Gamification Agent jobs."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ranking_agent import RankingAgentJob

ACTIVE_STATUSES: frozenset[str] = frozenset(
    {"queued", "calculating", "validating", "preview_ready", "applying"}
)
TERMINAL_STATUSES: frozenset[str] = frozenset({"completed", "failed", "cancelled"})

ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    "queued": {"calculating", "cancelled", "failed"},
    "calculating": {"validating", "cancelled", "failed"},
    "validating": {"preview_ready", "cancelled", "failed"},
    "preview_ready": {"applying", "cancelled", "queued", "failed"},
    "applying": {"completed", "failed"},
    "failed": {"queued"},
    "cancelled": {"queued"},
    "completed": set(),
}


def _utcnow() -> datetime:
    return datetime.now(UTC)


class RankingAgentJobService:
    @staticmethod
    async def create(
        db: AsyncSession,
        *,
        requested_by_id: uuid.UUID,
        job_type: str,
        config: dict,
    ) -> RankingAgentJob:
        job = RankingAgentJob(
            requested_by_id=requested_by_id,
            job_type=job_type,
            config=config,
            progress={"stage": "queued", "percent": 0, "counters": {}},
        )
        db.add(job)
        await db.flush()
        return job

    @staticmethod
    async def get(
        db: AsyncSession, job_id: uuid.UUID, *, lock: bool = False
    ) -> RankingAgentJob | None:
        query = select(RankingAgentJob).where(RankingAgentJob.id == job_id)
        if lock:
            query = query.with_for_update().execution_options(populate_existing=True)
        return await db.scalar(query)

    @staticmethod
    async def count_active_by_requester(
        db: AsyncSession, requester_id: uuid.UUID
    ) -> int:
        return await db.scalar(
            select(func.count(RankingAgentJob.id)).where(
                RankingAgentJob.requested_by_id == requester_id,
                RankingAgentJob.status.in_(ACTIVE_STATUSES),
            )
        ) or 0

    @staticmethod
    async def list(
        db: AsyncSession, *, limit: int = 50, offset: int = 0
    ) -> list[RankingAgentJob]:
        result = await db.execute(
            select(RankingAgentJob)
            .order_by(RankingAgentJob.created_at.desc())
            .offset(offset)
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def transition(
        db: AsyncSession,
        job: RankingAgentJob,
        status: str,
        *,
        percent: int | None = None,
        counters: dict | None = None,
    ) -> RankingAgentJob:
        if status != job.status and status not in ALLOWED_TRANSITIONS.get(job.status, set()):
            raise ValueError(f"Invalid ranking-agent job transition: {job.status} -> {status}")
        now = _utcnow()
        if job.started_at is None and status not in {"queued", "cancelled"}:
            job.started_at = now
        job.status = status
        progress = dict(job.progress or {})
        progress["stage"] = status
        if percent is not None:
            progress["percent"] = max(0, min(percent, 100))
        if counters is not None:
            progress["counters"] = counters
        job.progress = progress
        job.updated_at = now
        if status in TERMINAL_STATUSES:
            job.completed_at = now
        await db.flush()
        return job

    @staticmethod
    async def set_preview(
        db: AsyncSession,
        job: RankingAgentJob,
        *,
        artifact: dict,
        warnings: list[str],
        blocking_errors: list[str],
    ) -> RankingAgentJob:
        job.artifact = artifact
        job.warnings = warnings
        job.blocking_errors = blocking_errors
        return await RankingAgentJobService.transition(
            db, job, "preview_ready", percent=100
        )

    @staticmethod
    async def fail(
        db: AsyncSession, job: RankingAgentJob, message: str
    ) -> RankingAgentJob:
        job.error_message = message[:2000]
        if job.status in TERMINAL_STATUSES:
            return job
        return await RankingAgentJobService.transition(db, job, "failed")

    @staticmethod
    async def cancel(db: AsyncSession, job: RankingAgentJob) -> RankingAgentJob:
        if job.status in TERMINAL_STATUSES:
            raise ValueError(f"Cannot cancel a {job.status} job")
        return await RankingAgentJobService.transition(db, job, "cancelled")

    @staticmethod
    async def retry(db: AsyncSession, job: RankingAgentJob) -> RankingAgentJob:
        if job.status not in {"failed", "cancelled", "preview_ready"}:
            raise ValueError(f"Cannot retry a {job.status} job")
        job.error_message = None
        job.blocking_errors = []
        job.warnings = []
        job.artifact = None
        job.completed_at = None
        job.progress = {"stage": "queued", "percent": 0, "counters": {}}
        return await RankingAgentJobService.transition(db, job, "queued", percent=0)
