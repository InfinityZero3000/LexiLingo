"""Gem limits and the ledger of what admins have handed out."""
from datetime import date, datetime, time, timedelta, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core.database import get_db
from app.core.dependencies import get_current_super_admin, require_permission
from app.models.app_setting import AdminGemGrant
from app.models.user import User
from app.schemas.response import ApiResponse
from app.services.admin_audit import record_admin_action
from app.services.gem_limits import get_gem_limits, set_gem_limits, usage_for

router = APIRouter(prefix="/admin", tags=["Admin - Gem Ledger"])

_FIELD_TO_KEY = {
    "gift_max_admin": "gems.gift_max_per_action.admin",
    "gift_max_super_admin": "gems.gift_max_per_action.super_admin",
    "budget_admin": "gems.daily_budget.admin",
    "budget_super_admin": "gems.daily_budget.super_admin",
    "item_max_qty": "gems.item_gift_max_qty",
}


class GemLimitsUpdate(BaseModel):
    gift_max_admin: Optional[int] = Field(None, ge=1)
    gift_max_super_admin: Optional[int] = Field(None, ge=1)
    budget_admin: Optional[int] = Field(None, ge=0)
    budget_super_admin: Optional[int] = Field(None, ge=0)
    item_max_qty: Optional[int] = Field(None, ge=1)


def _config(limits: dict[str, int]) -> dict[str, int]:
    return {field: limits[key] for field, key in _FIELD_TO_KEY.items()}


@router.get("/gem-limits", response_model=ApiResponse[dict])
async def get_my_gem_limits(
    admin: User = Depends(require_permission("gifts:read")),
    db: AsyncSession = Depends(get_db),
):
    """The caller's per-action cap and what is left of today's budget; super admins also get the config."""
    data: dict = {"usage": await usage_for(db, admin)}
    if admin.role_level >= 2:
        data["config"] = _config(await get_gem_limits(db))
    return ApiResponse(success=True, message="Gem limits retrieved", data=data)


@router.put("/gem-limits", response_model=ApiResponse[dict])
async def update_gem_limits(
    data: GemLimitsUpdate,
    request: Request,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    updates = {_FIELD_TO_KEY[f]: v for f, v in data.model_dump(exclude_none=True).items()}
    before, after = await set_gem_limits(db, admin, updates)
    if after:
        record_admin_action(db, admin, "gem_limits_update", "app_settings", None, {"before": before, "after": after}, request)
    await db.commit()
    return ApiResponse(
        success=True,
        message="Gem limits updated",
        data={"config": _config(await get_gem_limits(db)), "usage": await usage_for(db, admin)},
    )


@router.get("/gem-grants", response_model=ApiResponse[dict])
async def list_gem_grants(
    kind: Optional[str] = Query(None, pattern="^(gift|adjust)$"),
    user_id: Optional[UUID] = None,
    actor_id: Optional[UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    admin: User = Depends(require_permission("gifts:read")),
    db: AsyncSession = Depends(get_db),
):
    """Newest first. A plain admin only sees their own grants."""
    actor = aliased(User)
    target = aliased(User)
    filters = []
    if admin.role_level < 2:
        filters.append(AdminGemGrant.actor_id == admin.id)
    elif actor_id:
        filters.append(AdminGemGrant.actor_id == actor_id)
    if kind:
        filters.append(AdminGemGrant.kind == kind)
    if user_id:
        filters.append(AdminGemGrant.user_id == user_id)
    if date_from:
        filters.append(AdminGemGrant.created_at >= datetime.combine(date_from, time.min, tzinfo=timezone.utc))
    if date_to:
        filters.append(
            AdminGemGrant.created_at < datetime.combine(date_to + timedelta(days=1), time.min, tzinfo=timezone.utc)
        )

    total = (await db.execute(select(func.count()).select_from(AdminGemGrant).where(*filters))).scalar() or 0
    rows = (
        await db.execute(
            select(AdminGemGrant, actor.username, target.username, target.email)
            .outerjoin(actor, actor.id == AdminGemGrant.actor_id)
            .outerjoin(target, target.id == AdminGemGrant.user_id)
            .where(*filters)
            .order_by(AdminGemGrant.created_at.desc())
            .offset(offset)
            .limit(limit)
        )
    ).all()
    return ApiResponse(
        success=True,
        message="Gem grants retrieved",
        data={
            "total": total,
            "items": [
                {
                    "id": str(g.id),
                    "kind": g.kind,
                    "amount": g.amount,
                    "reason": g.reason,
                    "created_at": g.created_at.isoformat() if g.created_at else None,
                    "actor": {"id": str(g.actor_id) if g.actor_id else None, "username": actor_name},
                    "user": {"id": str(g.user_id) if g.user_id else None, "username": user_name, "email": user_email},
                }
                for g, actor_name, user_name, user_email in rows
            ],
        },
    )
