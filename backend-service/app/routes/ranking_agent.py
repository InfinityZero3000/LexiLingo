"""Admin-only API for Ranking/Gamification Agent jobs."""

from __future__ import annotations

import json
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.celery_app import celery_app
from app.core.cache import invalidate_cache
from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import _get_user_role_level, get_current_admin
from app.models.rbac import AuditLog
from app.models.user import User
from app.schemas.ranking_agent import RankingAgentJobCreate, RankingAgentJobResponse
from app.schemas.response import ApiResponse
from app.services.ranking_agent.apply import RankingAgentApplyService
from app.services.ranking_agent_jobs import RankingAgentJobService
from app.tasks.ranking_agent import run_ranking_agent_job

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin/ranking-agent", tags=["Ranking Agent"])


def _require_enabled() -> None:
    if not settings.RANKING_AGENT_ENABLED:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ranking agent is disabled",
        )


def _job_response(job) -> RankingAgentJobResponse:
    return RankingAgentJobResponse.model_validate(job)


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
            resource_type="ranking_agent_job",
            resource_id=str(resource_id),
            details=json.dumps(details, sort_keys=True),
        )
    )


def _enqueue(job) -> None:
    result = run_ranking_agent_job.delay(str(job.id))
    job.celery_task_id = result.id


def _require_job_owner(job, admin: User) -> None:
    if _get_user_role_level(admin) < 2 and job.requested_by_id != admin.id:
        raise HTTPException(status_code=404, detail="Ranking-agent job not found")


@router.post(
    "/jobs",
    response_model=ApiResponse[RankingAgentJobResponse],
    status_code=status.HTTP_202_ACCEPTED,
)
async def create_job(
    payload: RankingAgentJobCreate,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    active_count = await RankingAgentJobService.count_active_by_requester(db, admin.id)
    if active_count >= settings.RANKING_AGENT_MAX_ACTIVE_JOBS_PER_ADMIN:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"You already have {active_count} active ranking-agent jobs. "
                "Wait for existing jobs to complete before creating more."
            ),
        )

    config = {
        "job_type": payload.job_type,
        **payload.config,
        "use_ai_insights": payload.use_ai_insights,
    }
    try:
        job = await RankingAgentJobService.create(
            db,
            requested_by_id=admin.id,
            job_type=payload.job_type,
            config=config,
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    _audit(
        db,
        admin=admin,
        action="create",
        resource_id=job.id,
        details={"job_type": payload.job_type, "config": payload.config},
    )
    await db.commit()

    try:
        _enqueue(job)
        await db.commit()
    except Exception:
        await RankingAgentJobService.fail(db, job, "Could not enqueue ranking-agent job")
        await db.commit()
        logger.exception("Could not enqueue ranking-agent job")
        raise HTTPException(status_code=503, detail="Ranking-agent worker unavailable")

    return ApiResponse(message="Ranking-agent job queued", data=_job_response(job))


@router.get("/jobs", response_model=ApiResponse[list[RankingAgentJobResponse]])
async def list_jobs(
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_admin),
):
    jobs = await RankingAgentJobService.list(db, limit=limit, offset=offset)
    return ApiResponse(data=[_job_response(j) for j in jobs])


async def _get_job_or_404(db: AsyncSession, job_id: uuid.UUID, *, lock: bool = False):
    job = await RankingAgentJobService.get(db, job_id, lock=lock)
    if job is None:
        raise HTTPException(status_code=404, detail="Ranking-agent job not found")
    return job


@router.get("/jobs/{job_id}", response_model=ApiResponse[RankingAgentJobResponse])
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
        job, result = await RankingAgentApplyService.apply(db, job_id)
        await db.commit()
        if job.job_type == "achievement_batch" and result.get("granted_count", 0) > 0:
            await invalidate_cache("leaderboard")
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    _audit(
        db,
        admin=admin,
        action="apply",
        resource_id=job.id,
        details={"result": result},
    )
    await db.commit()
    return ApiResponse(
        message="Ranking-agent job applied",
        data={"job": _job_response(job).model_dump(mode="json"), "result": result},
    )


@router.post("/jobs/{job_id}/cancel", response_model=ApiResponse[RankingAgentJobResponse])
async def cancel_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    job = await _get_job_or_404(db, job_id, lock=True)
    _require_job_owner(job, admin)
    try:
        await RankingAgentJobService.cancel(db, job)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    _audit(db, admin=admin, action="cancel", resource_id=job.id, details={})
    await db.commit()
    if job.celery_task_id and hasattr(celery_app, "control"):
        try:
            celery_app.control.revoke(job.celery_task_id, terminate=False)
        except Exception:
            logger.warning("Could not revoke ranking-agent task %s", job.celery_task_id)
    return ApiResponse(message="Ranking-agent job cancelled", data=_job_response(job))


@router.post("/jobs/{job_id}/retry", response_model=ApiResponse[RankingAgentJobResponse])
async def retry_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    _require_enabled()
    job = await _get_job_or_404(db, job_id, lock=True)
    _require_job_owner(job, admin)
    try:
        await RankingAgentJobService.retry(db, job)
        _audit(db, admin=admin, action="retry", resource_id=job.id, details={})
        await db.commit()
        _enqueue(job)
        await db.commit()
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except Exception:
        await RankingAgentJobService.fail(db, job, "Could not enqueue ranking-agent job")
        await db.commit()
        logger.exception("Could not requeue ranking-agent job")
        raise HTTPException(status_code=503, detail="Ranking-agent worker unavailable")
    return ApiResponse(message="Ranking-agent job requeued", data=_job_response(job))
