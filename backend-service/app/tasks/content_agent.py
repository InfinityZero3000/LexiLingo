"""Celery orchestration for CEFR course generation."""

from __future__ import annotations

import asyncio
import logging
import uuid
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from typing import TypeVar

import httpx
from pydantic import ValidationError
from sqlalchemy import delete

from app.core.celery_app import celery_app
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.content_agent import ContentAgentUpload
from app.schemas.content_agent import ContentAgentArtifact
from app.services.content_agent_apply import ContentAgentApplyService
from app.services.content_agent_client import ContentAgentClient
from app.services.content_agent_jobs import ContentAgentJobService
from app.services.content_agent_sources import (
    SourceResolutionError,
    get_source_catalog,
    resolve_snapshots,
)

logger = logging.getLogger(__name__)
T = TypeVar("T")


class JobCancelled(Exception):
    pass


@celery_app.task(name="app.tasks.content_agent.run_content_agent")
def run_content_agent(job_id: str) -> dict:
    return asyncio.run(_run_content_agent(uuid.UUID(job_id)))


async def _locked_active_job(db, job_id: uuid.UUID):
    job = await ContentAgentJobService.get(db, job_id, lock=True)
    if job is None:
        raise LookupError(f"Content-agent job {job_id} does not exist")
    if job.status == "cancelled":
        raise JobCancelled
    return job


def _is_transient_ai_error(exc: Exception) -> bool:
    if isinstance(exc, (httpx.TimeoutException, httpx.TransportError)):
        return True
    return (
        isinstance(exc, httpx.HTTPStatusError)
        and exc.response.status_code in {408, 429, 500, 502, 503, 504}
    )


async def _with_transient_retry(
    operation: Callable[[], Awaitable[T]],
    *,
    attempts: int = 3,
) -> T:
    for attempt in range(attempts):
        try:
            return await operation()
        except Exception as exc:
            if attempt == attempts - 1 or not _is_transient_ai_error(exc):
                raise
            await asyncio.sleep(0.25 * (2**attempt))
    raise RuntimeError("unreachable")


def _public_error_message(exc: Exception) -> str:
    if isinstance(exc, ValidationError):
        return "Generated content failed schema validation"
    if isinstance(exc, (httpx.TimeoutException, httpx.TransportError)):
        return "AI content service is temporarily unavailable"
    if isinstance(exc, httpx.HTTPStatusError):
        return f"AI content service request failed with status {exc.response.status_code}"
    if isinstance(exc, SourceResolutionError):
        return "Source resolution failed — check that all requested sources are approved and active"
    if isinstance(exc, ValueError):
        return "Content-agent input or generated content was invalid"
    return "Content-agent generation failed"


async def _ingest_batches(
    client: ContentAgentClient,
    job_id: uuid.UUID,
    records: list[dict],
    *,
    batch_size: int = 1000,
) -> None:
    for start in range(0, len(records), batch_size):
        batch = records[start : start + batch_size]
        await _with_transient_retry(
            lambda batch=batch: client.ingest_records(job_id, batch)
        )


async def _attach_pinned_snapshots(
    client: ContentAgentClient,
    job_id: uuid.UUID,
    pinned_snapshots: list[dict],
) -> None:
    if not pinned_snapshots:
        return
    await _with_transient_retry(
        lambda: client.attach_snapshots(job_id, pinned_snapshots)
    )


async def _run_content_agent(job_id: uuid.UUID) -> dict:
    async with AsyncSessionLocal() as db:
        job = await ContentAgentJobService.get(db, job_id, lock=True)
        if job is None:
            raise LookupError(f"Content-agent job {job_id} does not exist")
        if not settings.CONTENT_AGENT_ENABLED:
            await ContentAgentJobService.fail(db, job, "Content agent is disabled")
            await db.commit()
            return {"job_id": str(job_id), "status": "failed"}
        if job.status != "queued":
            return {"job_id": str(job_id), "status": job.status}

        client: ContentAgentClient | None = None
        try:
            client = ContentAgentClient()

            # -------------------------------------------------------------------
            # Stage: resolving_sources — pin snapshot IDs at job creation time.
            # On retry, reuse the snapshots already stored in config so results
            # are deterministic even if the catalog changes between attempts.
            # -------------------------------------------------------------------
            job = await _locked_active_job(db, job_id)
            await ContentAgentJobService.transition(
                db, job, "resolving_sources", percent=5
            )
            await db.commit()

            sources: list[str] = job.config.get("sources", [])
            pinned_snapshots: list[dict] = list(
                job.config.get("pinned_snapshots", [])
            )
            if not pinned_snapshots:
                catalog = await _with_transient_retry(
                    lambda: get_source_catalog(client)
                )
                pinned_snapshots = resolve_snapshots(sources, catalog)
                async with db.begin_nested():
                    job = await _locked_active_job(db, job_id)
                    config = dict(job.config)
                    config["pinned_snapshots"] = pinned_snapshots
                    job.config = config
                    await db.flush()
                await db.commit()

            # -------------------------------------------------------------------
            # Stage: loading_snapshots — signal AI service to load pinned data
            # -------------------------------------------------------------------
            job = await _locked_active_job(db, job_id)
            await ContentAgentJobService.transition(
                db, job, "loading_snapshots", percent=10
            )
            await db.commit()

            await _attach_pinned_snapshots(
                client,
                job.id,
                pinned_snapshots,
            )

            # -------------------------------------------------------------------
            # Stage: normalizing_upload — ingest admin upload if present
            # -------------------------------------------------------------------
            records: list[dict] = []
            if job.upload_id is not None and "admin_upload" in sources:
                upload = await db.get(ContentAgentUpload, job.upload_id)
                if upload is None:
                    raise ValueError("Referenced upload no longer exists")
                if upload.expires_at <= datetime.now(UTC):
                    raise ValueError("Referenced upload has expired")
                if not upload.rights_confirmed:
                    raise ValueError(
                        "Upload rights attestation is required before use in a job"
                    )
                records = [
                    {
                        **record,
                        "raw_checksum": upload.checksum,
                        "source_version": record.get(
                            "source_version",
                            "job-upload-v1",
                        ),
                        "source_record_id": record.get("source_record_id")
                        or record.get("record_id"),
                        "license_id": "LicenseRef-Admin-Owned",
                        "license_url": (
                            "https://lexilingo.me/legal/content-upload-rights"
                        ),
                        "attribution_text": (
                            "Administrator-owned or licensed upload"
                        ),
                    }
                    for record in upload.records
                ]

            job = await _locked_active_job(db, job_id)
            await ContentAgentJobService.transition(
                db, job, "normalizing_upload", percent=15
            )
            await db.commit()

            if records:
                await _ingest_batches(client, job.id, records)

            # -------------------------------------------------------------------
            # Stages: classifying → planning → generating
            # -------------------------------------------------------------------
            stages = [
                ("classifying", 35),
                ("planning", 55),
                ("generating", 70),
            ]
            for stage, percent in stages:
                job = await _locked_active_job(db, job_id)
                await ContentAgentJobService.transition(
                    db,
                    job,
                    stage,
                    percent=percent,
                    counters={"input_records": len(records)},
                )
                await db.commit()

            try:
                artifact_payload = await _with_transient_retry(
                    lambda: client.generate(job.id, dict(job.config))
                )
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code != 404 or not records:
                    raise
                await _ingest_batches(client, job.id, records)
                artifact_payload = await _with_transient_retry(
                    lambda: client.generate(job.id, dict(job.config))
                )

            # -------------------------------------------------------------------
            # Stage: validating
            # -------------------------------------------------------------------
            job = await _locked_active_job(db, job_id)
            await ContentAgentJobService.transition(db, job, "validating", percent=90)
            await db.commit()

            artifact = ContentAgentArtifact.model_validate(artifact_payload)
            job = await _locked_active_job(db, job_id)
            await ContentAgentJobService.set_preview(
                db,
                job,
                artifact=artifact.model_dump(mode="json"),
                source_manifest=[
                    item.model_dump(mode="json")
                    for item in artifact.source_manifest
                ],
                warnings=artifact.quality.warnings,
                blocking_errors=artifact.quality.blocking_errors,
            )
            await db.commit()

            # apply_on_success is honoured but preview blocking is the default;
            # admin must explicitly call /apply unless this flag is set.
            if job.config.get("apply_on_success") and not job.blocking_errors:
                await ContentAgentApplyService.apply(db, job.id)
                await db.commit()

            logger.info("Content-agent job %s reached %s", job.id, job.status)
            return {"job_id": str(job.id), "status": job.status}
        except JobCancelled:
            await db.rollback()
            return {"job_id": str(job_id), "status": "cancelled"}
        except Exception as exc:
            await db.rollback()
            job = await ContentAgentJobService.get(db, job_id)
            if job is not None and job.status != "cancelled":
                await ContentAgentJobService.fail(
                    db, job, _public_error_message(exc)
                )
                await db.commit()
            logger.exception("Content-agent job %s failed", job_id)
            raise
        finally:
            if client is not None:
                try:
                    await client.delete_context(job_id)
                except Exception:
                    logger.warning(
                        "Could not delete AI content-agent context for %s",
                        job_id,
                        exc_info=True,
                    )


@celery_app.task(
    name="app.tasks.content_agent.cleanup_expired_content_agent_uploads"
)
def cleanup_expired_content_agent_uploads() -> int:
    return asyncio.run(_cleanup_expired_content_agent_uploads())


async def _cleanup_expired_content_agent_uploads() -> int:
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            delete(ContentAgentUpload).where(
                ContentAgentUpload.expires_at <= datetime.now(UTC)
            )
        )
        await db.commit()
        return result.rowcount or 0
