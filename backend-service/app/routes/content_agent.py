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
from app.core.dependencies import _get_user_role_level, get_current_admin
from app.models.content_agent import ContentAgentUpload
from app.models.rbac import AuditLog
from app.models.user import User
from app.schemas.content_agent import (
    ContentAgentJobCreate,
    ContentAgentJobResponse,
    ContentAgentUploadResponse,
    SourceSnapshotDescriptor,
)
from app.schemas.response import ApiResponse
from app.services.content_agent_apply import ContentAgentApplyService
from app.services.content_agent_client import ContentAgentClient
from app.services.content_agent_jobs import ContentAgentJobService
from app.services.content_agent_sources import (
    SourceResolutionError,
    canonicalize_sources,
    get_source_catalog,
    resolve_snapshots,
)
from app.services.content_agent_uploads import (
    MAX_UPLOAD_BYTES,
    detect_upload_format,
    parse_content_upload,
)
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
    rights_confirmed: bool = Query(
        default=False,
        description=(
            "Must be true to attest that the uploader has rights to use "
            "this content in LexiLingo. Uploads without attestation cannot "
            "be used in content-agent jobs."
        ),
    ),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    if not rights_confirmed:
        raise HTTPException(
            status_code=422,
            detail="Upload rights attestation is required",
        )
    content = await file.read(MAX_UPLOAD_BYTES + 1)
    await file.close()
    try:
        upload_format = detect_upload_format(file.filename or "upload", content)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    allowed_types_by_format = {
        "csv": {"text/csv", "application/csv", "application/octet-stream"},
        "json": {"application/json", "text/json", "application/octet-stream"},
    }
    if file.content_type is not None and file.content_type not in (
        allowed_types_by_format[upload_format]
    ):
        raise HTTPException(status_code=415, detail="Unsupported upload MIME type")
    try:
        parsed = parse_content_upload(
            file.filename or "upload",
            content,
            rights_confirmed=rights_confirmed,
        )
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
        schema_version=parsed.schema_version,
        records=parsed.records,
        expires_at=datetime.now(UTC)
        + timedelta(days=settings.CONTENT_AGENT_UPLOAD_TTL_DAYS),
        rights_confirmed=parsed.rights_confirmed,
        rights_confirmed_at=parsed.rights_confirmed_at,
        uploader_id=admin.id,
    )
    db.add(upload)
    await db.flush()
    return ApiResponse(
        message="Upload validated",
        data=ContentAgentUploadResponse.model_validate(upload),
    )


@router.get(
    "/sources",
    response_model=ApiResponse[list[SourceSnapshotDescriptor]],
)
async def list_sources(
    _: User = Depends(get_current_admin),
):
    _require_enabled()
    try:
        catalog = await get_source_catalog(ContentAgentClient())
        descriptors = [
            SourceSnapshotDescriptor.model_validate(entry)
            for entry in catalog
        ]
    except Exception as exc:
        logger.warning("Could not load content-agent source catalog", exc_info=True)
        raise HTTPException(
            status_code=503,
            detail="Content-agent source catalog is unavailable",
        ) from exc
    return ApiResponse(data=descriptors)


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
    active_count = await ContentAgentJobService.count_active_by_requester(db, admin.id)
    if active_count >= settings.CONTENT_AGENT_MAX_ACTIVE_JOBS_PER_ADMIN:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"You already have {active_count} active content-agent jobs. "
                "Wait for existing jobs to complete before creating more."
            ),
        )
    if payload.upload_id is not None:
        upload = await db.get(ContentAgentUpload, payload.upload_id)
        if upload is None or upload.uploaded_by_id != admin.id:
            raise HTTPException(status_code=404, detail="Upload not found")
        if upload.expires_at <= datetime.now(UTC):
            raise HTTPException(status_code=410, detail="Upload has expired")
        if not upload.rights_confirmed:
            raise HTTPException(
                status_code=422,
                detail="Upload rights attestation is required",
            )
    canonical_sources = canonicalize_sources(payload.sources)
    real_sources = [
        source for source in canonical_sources if source != "admin_upload"
    ]
    try:
        catalog = (
            await get_source_catalog(ContentAgentClient())
            if real_sources
            else []
        )
        pinned_snapshots = resolve_snapshots(canonical_sources, catalog)
    except SourceResolutionError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        logger.warning("Could not resolve content-agent sources", exc_info=True)
        raise HTTPException(
            status_code=503,
            detail="Content-agent source catalog is unavailable",
        ) from exc
    resolved_payload = ContentAgentJobCreate.model_validate(
        {
            **payload.model_dump(mode="json"),
            "sources": canonical_sources,
            "pinned_snapshots": pinned_snapshots,
            "source_ids": [
                snapshot["snapshot_id"] for snapshot in pinned_snapshots
            ],
        }
    )
    try:
        job = await ContentAgentJobService.create(
            db, requested_by_id=admin.id, config=resolved_payload
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    _audit(
        db,
        admin=admin,
        action="create",
        resource_id=job.id,
        details={"config": resolved_payload.model_dump(mode="json")},
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


def _require_job_owner(job, admin: User) -> None:
    """Super-admins may touch any job; regular admins only their own.

    Returns 404 (not 403) to prevent BOLA enumeration — callers cannot
    distinguish "job doesn't exist" from "job belongs to another admin".
    """
    if _get_user_role_level(admin) < 2 and job.requested_by_id != admin.id:
        raise HTTPException(status_code=404, detail="Content-agent job not found")


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
    _require_job_owner(await _get_job_or_404(db, job_id), admin)
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
    _require_job_owner(job, admin)
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
    _require_job_owner(job, admin)
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
