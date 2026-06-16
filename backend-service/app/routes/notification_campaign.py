"""Admin-only API for Notification Campaign Agent jobs."""

from __future__ import annotations

import json
import logging
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.celery_app import celery_app
from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import _get_user_role_level, get_current_admin
from app.models.rbac import AuditLog
from app.models.user import User
from app.schemas.notification_campaign import (
    NotificationCampaignJobCreate,
    NotificationCampaignJobResponse,
)
from app.schemas.response import ApiResponse
from app.services.notification_campaign.apply import NotificationCampaignApplyService
from app.services.notification_campaign_jobs import (
    ACTIVE_STATUSES,
    NotificationCampaignJobService,
)
from app.tasks.notification_campaign import run_notification_campaign_job

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin/notification-campaign", tags=["Notification Campaign"])


def _require_enabled() -> None:
    if not settings.NOTIFICATION_CAMPAIGN_ENABLED:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Notification campaign agent is disabled",
        )


def _job_response(job) -> NotificationCampaignJobResponse:
    return NotificationCampaignJobResponse.model_validate(job)


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
            resource_type="notification_campaign_job",
            resource_id=str(resource_id),
            details=json.dumps(details, sort_keys=True),
        )
    )


def _enqueue(job) -> None:
    result = run_notification_campaign_job.delay(str(job.id))
    job.celery_task_id = result.id


def _require_job_owner(job, admin: User) -> None:
    if _get_user_role_level(admin) < 2 and job.requested_by_id != admin.id:
        raise HTTPException(status_code=404, detail="Notification-campaign job not found")


@router.post(
    "/jobs",
    response_model=ApiResponse[NotificationCampaignJobResponse],
    status_code=status.HTTP_202_ACCEPTED,
)
async def create_job(
    payload: NotificationCampaignJobCreate,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    active_count = await NotificationCampaignJobService.count_active_by_requester(db, admin.id)
    if active_count >= settings.NOTIFICATION_CAMPAIGN_MAX_ACTIVE_JOBS_PER_ADMIN:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"You already have {active_count} active notification-campaign jobs. "
                "Wait for existing jobs to complete before creating more."
            ),
        )

    config = {"job_type": payload.job_type, **payload.config}
    job = await NotificationCampaignJobService.create(
        db,
        requested_by_id=admin.id,
        job_type=payload.job_type,
        config=config,
    )
    _enqueue(job)
    _audit(db, admin=admin, action="create_notification_campaign_job", resource_id=job.id, details={"job_type": payload.job_type})
    await db.commit()
    await db.refresh(job)
    return ApiResponse(data=_job_response(job))


@router.get(
    "/jobs",
    response_model=ApiResponse[list[NotificationCampaignJobResponse]],
)
async def list_jobs(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    requester_filter = None if _get_user_role_level(admin) >= 2 else admin.id
    jobs = await NotificationCampaignJobService.list_jobs(
        db, limit=limit, offset=offset, requested_by_id=requester_filter
    )
    return ApiResponse(data=[_job_response(j) for j in jobs])


@router.get(
    "/jobs/{job_id}",
    response_model=ApiResponse[NotificationCampaignJobResponse],
)
async def get_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    job = await NotificationCampaignJobService.get(db, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Notification-campaign job not found")
    _require_job_owner(job, admin)
    return ApiResponse(data=_job_response(job))


@router.post(
    "/jobs/{job_id}/apply",
    response_model=ApiResponse[NotificationCampaignJobResponse],
)
async def apply_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    job = await NotificationCampaignJobService.get(db, job_id, lock=True)
    if job is None:
        raise HTTPException(status_code=404, detail="Notification-campaign job not found")
    _require_job_owner(job, admin)

    if job.status != "preview_ready":
        raise HTTPException(
            status_code=409,
            detail=f"Job is in status '{job.status}' — can only apply 'preview_ready' jobs.",
        )
    if job.blocking_errors:
        raise HTTPException(
            status_code=422,
            detail="Job has blocking errors and cannot be applied.",
        )
    if job.job_type == "scheduled_push":
        send_at_raw = job.config.get("send_at")
        if send_at_raw:
            try:
                send_at = datetime.fromisoformat(str(send_at_raw).replace("Z", "+00:00"))
                if send_at.tzinfo is None:
                    send_at = send_at.replace(tzinfo=UTC)
                if datetime.now(UTC) < send_at:
                    raise HTTPException(
                        status_code=409,
                        detail=f"Scheduled send time has not arrived yet ({send_at_raw}).",
                    )
            except ValueError:
                raise HTTPException(
                    status_code=422,
                    detail=f"Invalid send_at format in job config: {send_at_raw!r}",
                )

    await NotificationCampaignJobService.transition(db, job, "sending", percent=0, stage="sending")
    await db.commit()

    try:
        result = await NotificationCampaignApplyService.apply(db, job)
        await NotificationCampaignJobService.transition(db, job, "completed", percent=100, stage="completed")
        _audit(
            db,
            admin=admin,
            action="apply_notification_campaign_job",
            resource_id=job.id,
            details={"job_type": job.job_type, **result},
        )
        await db.commit()
        await db.refresh(job)
        return ApiResponse(data=_job_response(job))
    except Exception as exc:
        await db.rollback()
        async with db.begin():
            job = await NotificationCampaignJobService.get(db, job_id, lock=True)
            if job:
                await NotificationCampaignJobService.set_failed(db, job, str(exc))
        raise HTTPException(status_code=500, detail=str(exc))


@router.post(
    "/jobs/{job_id}/cancel",
    response_model=ApiResponse[NotificationCampaignJobResponse],
)
async def cancel_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    job = await NotificationCampaignJobService.get(db, job_id, lock=True)
    if job is None:
        raise HTTPException(status_code=404, detail="Notification-campaign job not found")
    _require_job_owner(job, admin)

    if job.status not in ACTIVE_STATUSES or job.status == "sending":
        raise HTTPException(
            status_code=409,
            detail=f"Cannot cancel job in status '{job.status}'.",
        )

    await NotificationCampaignJobService.transition(db, job, "cancelled")
    _audit(db, admin=admin, action="cancel_notification_campaign_job", resource_id=job.id, details={})
    await db.commit()
    await db.refresh(job)
    return ApiResponse(data=_job_response(job))


@router.post(
    "/jobs/{job_id}/retry",
    response_model=ApiResponse[NotificationCampaignJobResponse],
    status_code=status.HTTP_202_ACCEPTED,
)
async def retry_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    job = await NotificationCampaignJobService.get(db, job_id, lock=True)
    if job is None:
        raise HTTPException(status_code=404, detail="Notification-campaign job not found")
    _require_job_owner(job, admin)

    if job.status not in ("failed", "cancelled"):
        raise HTTPException(
            status_code=409,
            detail=f"Can only retry 'failed' or 'cancelled' jobs (current: '{job.status}').",
        )

    await NotificationCampaignJobService.transition(db, job, "queued")
    job.error_message = None
    _enqueue(job)
    _audit(db, admin=admin, action="retry_notification_campaign_job", resource_id=job.id, details={})
    await db.commit()
    await db.refresh(job)
    return ApiResponse(data=_job_response(job))
