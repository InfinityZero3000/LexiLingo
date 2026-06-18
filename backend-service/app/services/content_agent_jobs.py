"""Application service for durable content-agent jobs."""

from __future__ import annotations

import hashlib
import json
import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_agent import ContentAgentJob
from app.schemas.content_agent import ContentAgentJobCreate

ACTIVE_STATUSES = {
    "queued",
    "resolving_sources",
    "loading_snapshots",
    "normalizing_upload",
    "extracting",
    "normalizing",
    "classifying",
    "planning",
    "generating",
    "validating",
    "preview_ready",
    "applying",
}
TERMINAL_STATUSES = {"completed", "failed", "cancelled"}
ALLOWED_TRANSITIONS = {
    "queued": {"resolving_sources", "extracting", "cancelled", "failed"},
    "resolving_sources": {"loading_snapshots", "cancelled", "failed"},
    "loading_snapshots": {"normalizing_upload", "extracting", "cancelled", "failed"},
    "normalizing_upload": {"classifying", "cancelled", "failed"},
    # Legacy / direct path without source resolution
    "extracting": {"normalizing", "classifying", "cancelled", "failed"},
    "normalizing": {"classifying", "cancelled", "failed"},
    "classifying": {"planning", "cancelled", "failed"},
    "planning": {"generating", "cancelled", "failed"},
    "generating": {"validating", "cancelled", "failed"},
    "validating": {"preview_ready", "applying", "cancelled", "failed"},
    "preview_ready": {"applying", "cancelled", "queued", "failed"},
    "applying": {"completed", "failed"},
    "failed": {"queued"},
    "cancelled": {"queued"},
    "completed": set(),
}


def _utcnow() -> datetime:
    return datetime.now(UTC)


def request_hash(config: ContentAgentJobCreate) -> str:
    payload = config.model_dump(mode="json", exclude={"revision"})
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


class ContentAgentJobService:
    @staticmethod
    async def create(
        db: AsyncSession,
        *,
        requested_by_id: uuid.UUID,
        config: ContentAgentJobCreate,
    ) -> ContentAgentJob:
        digest = request_hash(config)
        active = await db.scalar(
            select(ContentAgentJob).where(
                ContentAgentJob.request_hash == digest,
                ContentAgentJob.status.in_(ACTIVE_STATUSES),
            )
        )
        if active is not None and not config.revision:
            raise ValueError(f"An active job already exists: {active.id}")

        revision = (
            await db.scalar(
                select(func.max(ContentAgentJob.revision)).where(
                    ContentAgentJob.request_hash == digest
                )
            )
            or 0
        ) + 1
        job = ContentAgentJob(
            requested_by_id=requested_by_id,
            upload_id=config.upload_id,
            request_hash=digest,
            revision=revision,
            config=config.model_dump(mode="json"),
            progress={"stage": "queued", "percent": 0, "counters": {}},
        )
        try:
            async with db.begin_nested():
                db.add(job)
                await db.flush()
        except IntegrityError as exc:
            raise ValueError(
                "A matching content-agent revision was created concurrently"
            ) from exc
        return job

    @staticmethod
    async def get(
        db: AsyncSession, job_id: uuid.UUID, *, lock: bool = False
    ) -> ContentAgentJob | None:
        query = select(ContentAgentJob).where(ContentAgentJob.id == job_id)
        if lock:
            query = query.with_for_update().execution_options(populate_existing=True)
        return await db.scalar(query)

    @staticmethod
    async def count_active_by_requester(
        db: AsyncSession, requester_id: uuid.UUID
    ) -> int:
        return await db.scalar(
            select(func.count(ContentAgentJob.id)).where(
                ContentAgentJob.requested_by_id == requester_id,
                ContentAgentJob.status.in_(ACTIVE_STATUSES),
            )
        ) or 0

    @staticmethod
    async def list(
        db: AsyncSession, *, limit: int = 50, offset: int = 0
    ) -> list[ContentAgentJob]:
        result = await db.execute(
            select(ContentAgentJob)
            .order_by(ContentAgentJob.created_at.desc())
            .offset(offset)
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def transition(
        db: AsyncSession,
        job: ContentAgentJob,
        status: str,
        *,
        percent: int | None = None,
        counters: dict | None = None,
    ) -> ContentAgentJob:
        if status != job.status and status not in ALLOWED_TRANSITIONS.get(job.status, set()):
            raise ValueError(f"Invalid job transition: {job.status} -> {status}")
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
        job: ContentAgentJob,
        *,
        artifact: dict,
        source_manifest: list[dict],
        warnings: list[str],
        blocking_errors: list[str],
    ) -> ContentAgentJob:
        job.artifact = artifact
        job.source_manifest = source_manifest
        job.warnings = warnings
        job.blocking_errors = blocking_errors
        return await ContentAgentJobService.transition(
            db, job, "preview_ready", percent=100
        )

    @staticmethod
    async def fail(
        db: AsyncSession, job: ContentAgentJob, message: str
    ) -> ContentAgentJob:
        job.error_message = message[:2000]
        if job.status in TERMINAL_STATUSES:
            return job
        return await ContentAgentJobService.transition(db, job, "failed")

    @staticmethod
    async def cancel(db: AsyncSession, job: ContentAgentJob) -> ContentAgentJob:
        if job.status in TERMINAL_STATUSES:
            raise ValueError(f"Cannot cancel a {job.status} job")
        return await ContentAgentJobService.transition(db, job, "cancelled")

    @staticmethod
    async def retry(db: AsyncSession, job: ContentAgentJob) -> ContentAgentJob:
        if job.status not in {"failed", "cancelled", "preview_ready"}:
            raise ValueError(f"Cannot retry a {job.status} job")
        job.error_message = None
        job.blocking_errors = []
        job.warnings = []
        job.artifact = None
        job.completed_at = None
        job.progress = {"stage": "queued", "percent": 0, "counters": {}}
        return await ContentAgentJobService.transition(db, job, "queued", percent=0)
