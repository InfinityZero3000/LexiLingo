"""Grouped errors and the settings of the email reports (see docs/operations/ERROR_MONITORING.md)."""
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_super_admin, require_permission
from app.models.ops_error import OpsErrorCount, OpsErrorGroup
from app.models.user import User
from app.schemas.response import ApiResponse
from app.services import ops_errors
from app.services.admin_audit import record_admin_action

router = APIRouter(prefix="/admin/ops", tags=["Admin - Operations"])

MAX_GROUPS = 200


class ErrorStateUpdate(BaseModel):
    state: Literal["open", "resolved", "muted"]


async def _count_window(db: AsyncSession, fingerprint: str, hours: int = 24) -> int:
    since = (datetime.now(UTC) - timedelta(hours=hours)).replace(minute=0, second=0, microsecond=0)
    return int(
        (
            await db.execute(
                select(func.coalesce(func.sum(OpsErrorCount.count), 0)).where(
                    OpsErrorCount.fingerprint == fingerprint, OpsErrorCount.bucket_start >= since
                )
            )
        ).scalar()
        or 0
    )


@router.get("/errors", response_model=ApiResponse[dict])
async def list_errors(
    hours: int = Query(24, ge=1, le=720),
    service: str = Query("", max_length=30),
    state: str = Query("open", pattern="^(open|resolved|muted|all)$"),
    kind: str = Query("", pattern="^(error|client)?$"),
    admin: User = Depends(require_permission("ops:read")),
    db: AsyncSession = Depends(get_db),
):
    since = (datetime.now(UTC) - timedelta(hours=hours)).replace(minute=0, second=0, microsecond=0)
    window = func.sum(OpsErrorCount.count).label("count_window")
    query = (
        select(OpsErrorGroup, window)
        .join(OpsErrorCount, OpsErrorCount.fingerprint == OpsErrorGroup.fingerprint)
        .where(OpsErrorCount.bucket_start >= since)
        .group_by(OpsErrorGroup.fingerprint)
        .order_by(window.desc(), OpsErrorGroup.last_seen.desc())
    )
    if service:
        query = query.where(OpsErrorGroup.service == service)
    if state != "all":
        query = query.where(OpsErrorGroup.state == state)
    if kind:
        query = query.where(OpsErrorGroup.kind == kind)
    rows = (await db.execute(query)).all()
    by_service: dict[str, int] = {}
    for group, count in rows:
        by_service[group.service] = by_service.get(group.service, 0) + int(count)
    return ApiResponse(
        success=True,
        message="Errors retrieved",
        data={
            "groups": [ops_errors.group_dict(g, int(c)) for g, c in rows[:MAX_GROUPS]],
            "totals": {"errors": sum(by_service.values()), "groups": len(rows), "by_service": by_service},
        },
    )


@router.patch("/errors/{fingerprint}", response_model=ApiResponse[dict])
async def set_error_state(
    fingerprint: str,
    body: ErrorStateUpdate,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    group = await db.get(OpsErrorGroup, fingerprint)
    if group is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Error group not found")
    before = group.state
    group.state = body.state
    group.regressed = False
    group.state_changed_by = admin.id
    group.state_changed_at = datetime.now(UTC)
    record_admin_action(
        db, admin, "ops_error_state", "ops_error_group", None,
        {"fingerprint": fingerprint, "before": before, "after": body.state}, request,
    )
    await db.commit()
    if before != body.state:
        await ops_errors.clear_alert_cooldown(fingerprint)
    return ApiResponse(
        success=True, message="Error group updated",
        data=ops_errors.group_dict(group, await _count_window(db, fingerprint)),
    )


@router.get("/error-report/settings", response_model=ApiResponse[dict])
async def get_error_report_settings(
    admin: User = Depends(require_permission("ops:read")),
    db: AsyncSession = Depends(get_db),
):
    return ApiResponse(success=True, message="Settings retrieved", data=await ops_errors.get_report_settings(db))


@router.put("/error-report/settings", response_model=ApiResponse[dict])
async def update_error_report_settings(
    body: ops_errors.ErrorReportSettingsUpdate,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    before, after = await ops_errors.set_report_settings(db, admin.id, body)
    if after:
        record_admin_action(db, admin, "error_report_settings_update", "app_settings", None,
                            {"before": before, "after": after}, request)
    await db.commit()
    return ApiResponse(success=True, message="Settings updated", data=await ops_errors.get_report_settings(db))


@router.post("/error-report/test", response_model=ApiResponse[dict])
async def send_error_report_test(
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    if not settings.SMTP_HOST:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Email is not configured: SMTP_HOST is not set")
    sent, groups = await ops_errors.send_test_report(db)
    if not sent:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "The test report could not be sent to any recipient")
    return ApiResponse(success=True, message="Test report sent", data={"sent_to": sent, "groups": groups})
