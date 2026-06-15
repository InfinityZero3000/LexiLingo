"""Admin-only API for CEFR content-agent jobs."""

from __future__ import annotations

import json
import logging
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.celery_app import celery_app
from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_admin
from app.models.content_agent import ContentAgentUpload
from app.models.rbac import AuditLog
from app.models.user import User
from app.schemas.content_agent import (
    ContentAgentJobCreate,
    ContentAgentJobResponse,
    ContentAgentUploadResponse,
)
from app.schemas.response import ApiResponse
from app.services.content_agent_apply import ContentAgentApplyService
from app.services.content_agent_jobs import ContentAgentJobService
from app.services.content_agent_uploads import MAX_UPLOAD_BYTES, parse_content_upload
from app.tasks.content_agent import run_content_agent

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin/content-agent", tags=["Content Agent"])


def _require_enabled() -> None:
    if not settings.CONTENT_AGENT_ENABLED:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Content agent is disabled",
        )
    if not settings.CONTENT_AGENT_SERVICE_TOKEN.strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Content agent service token is not configured",
        )


def _job_response(job) -> ContentAgentJobResponse:
    return ContentAgentJobResponse.model_validate(job)


def _audit(
    db: AsyncSession,
    *,
    admin: User,
    action: str,
    resource_id: uuid.UUID,
    details: dict,
) -> None:
    db.add(
        AuditLog(
            user_id=admin.id,
            action=action,
            resource_type="content_agent_job",
            resource_id=str(resource_id),
            details=json.dumps(details, sort_keys=True),
        )
    )


def _enqueue(job) -> None:
    result = run_content_agent.delay(str(job.id))
    job.celery_task_id = result.id


@router.post(
    "/uploads",
    response_model=ApiResponse[ContentAgentUploadResponse],
    status_code=status.HTTP_201_CREATED,
)
async def upload_source_file(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    allowed_types = {
        "text/csv",
        "application/csv",
        "application/json",
        "text/json",
        "application/octet-stream",
    }
    if file.content_type and file.content_type not in allowed_types:
        raise HTTPException(status_code=415, detail="Unsupported upload MIME type")
    content = await file.read(MAX_UPLOAD_BYTES + 1)
    await file.close()
    try:
        parsed = parse_content_upload(file.filename or "upload", content)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    if parsed.errors:
        raise HTTPException(
            status_code=422,
            detail={"message": "Upload contains invalid rows", "errors": parsed.errors},
        )

    upload = ContentAgentUpload(
        uploaded_by_id=admin.id,
        filename=parsed.filename,
        checksum=parsed.checksum,
        row_count=len(parsed.records),
        records=parsed.records,
        expires_at=datetime.now(UTC)
        + timedelta(days=settings.CONTENT_AGENT_UPLOAD_TTL_DAYS),
    )
    db.add(upload)
    await db.flush()
    return ApiResponse(
        message="Upload validated",
        data=ContentAgentUploadResponse.model_validate(upload),
    )


@router.post(
    "/jobs",
    response_model=ApiResponse[ContentAgentJobResponse],
    status_code=status.HTTP_202_ACCEPTED,
)
async def create_job(
    payload: ContentAgentJobCreate,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    if payload.upload_id is not None:
        upload = await db.get(ContentAgentUpload, payload.upload_id)
        if upload is None or upload.uploaded_by_id != admin.id:
            raise HTTPException(status_code=404, detail="Upload not found")
        if upload.expires_at <= datetime.now(UTC):
            raise HTTPException(status_code=410, detail="Upload has expired")
    try:
        job = await ContentAgentJobService.create(
            db, requested_by_id=admin.id, config=payload
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    _audit(
        db,
        admin=admin,
        action="create",
        resource_id=job.id,
        details={"config": payload.model_dump(mode="json")},
    )
    await db.commit()
    try:
        _enqueue(job)
        await db.commit()
    except Exception:
        await ContentAgentJobService.fail(
            db, job, "Could not enqueue content-agent job"
        )
        await db.commit()
        logger.exception("Could not enqueue content-agent job")
        raise HTTPException(status_code=503, detail="Content-agent worker unavailable")
    return ApiResponse(message="Content-agent job queued", data=_job_response(job))


@router.get("/jobs", response_model=ApiResponse[list[ContentAgentJobResponse]])
async def list_jobs(
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_admin),
):
    jobs = await ContentAgentJobService.list(db, limit=limit, offset=offset)
    return ApiResponse(data=[_job_response(job) for job in jobs])


async def _get_job_or_404(
    db: AsyncSession, job_id: uuid.UUID, *, lock: bool = False
):
    job = await ContentAgentJobService.get(db, job_id, lock=lock)
    if job is None:
        raise HTTPException(status_code=404, detail="Content-agent job not found")
    return job


@router.get(
    "/jobs/{job_id}", response_model=ApiResponse[ContentAgentJobResponse]
)
async def get_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_admin),
):
    return ApiResponse(data=_job_response(await _get_job_or_404(db, job_id)))


@router.get("/jobs/{job_id}/preview", response_model=ApiResponse[dict])
async def get_preview(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_admin),
):
    job = await _get_job_or_404(db, job_id)
    if not job.artifact:
        raise HTTPException(status_code=409, detail="Preview is not ready")
    return ApiResponse(
        data={
            "artifact": job.artifact,
            "warnings": job.warnings,
            "blocking_errors": job.blocking_errors,
        }
    )


@router.post("/jobs/{job_id}/apply", response_model=ApiResponse[dict])
async def apply_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    try:
        job, course_ids = await ContentAgentApplyService.apply(db, job_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    _audit(
        db,
        admin=admin,
        action="apply",
        resource_id=job.id,
        details={"course_ids": [str(course_id) for course_id in course_ids]},
    )
    return ApiResponse(
        message="Draft courses created",
        data={
            "job": _job_response(job).model_dump(mode="json"),
            "course_ids": [str(course_id) for course_id in course_ids],
        },
    )


@router.post(
    "/jobs/{job_id}/retry", response_model=ApiResponse[ContentAgentJobResponse]
)
async def retry_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    job = await _get_job_or_404(db, job_id, lock=True)
    try:
        await ContentAgentJobService.retry(db, job)
        _audit(db, admin=admin, action="retry", resource_id=job.id, details={})
        await db.commit()
        _enqueue(job)
        await db.commit()
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except Exception:
        await ContentAgentJobService.fail(
            db, job, "Could not enqueue content-agent job"
        )
        await db.commit()
        logger.exception("Could not requeue content-agent job")
        raise HTTPException(status_code=503, detail="Content-agent worker unavailable")
    return ApiResponse(message="Content-agent job requeued", data=_job_response(job))


@router.post(
    "/jobs/{job_id}/cancel", response_model=ApiResponse[ContentAgentJobResponse]
)
async def cancel_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    job = await _get_job_or_404(db, job_id, lock=True)
    try:
        await ContentAgentJobService.cancel(db, job)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    _audit(db, admin=admin, action="cancel", resource_id=job.id, details={})
    await db.commit()
    if job.celery_task_id and hasattr(celery_app, "control"):
        try:
            celery_app.control.revoke(job.celery_task_id, terminate=False)
        except Exception:
            logger.warning(
                "Could not revoke content-agent task %s",
                job.celery_task_id,
                exc_info=True,
            )
    return ApiResponse(message="Content-agent job cancelled", data=_job_response(job))
