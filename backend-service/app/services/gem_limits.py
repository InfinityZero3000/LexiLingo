"""Gem gift limits: editable in app_settings, env values in config.py are the defaults."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.app_setting import AdminGemGrant, AppSetting
from app.models.user import User

# key -> (config default, lowest value an operator may set)
GEM_LIMIT_KEYS: dict[str, tuple[str, int]] = {
    "gems.gift_max_per_action.admin": ("ADMIN_GIFT_MAX_GEMS", 1),
    "gems.gift_max_per_action.super_admin": ("SUPER_ADMIN_GIFT_MAX_GEMS", 1),
    "gems.daily_budget.admin": ("ADMIN_GIFT_DAILY_BUDGET_GEMS", 0),
    "gems.daily_budget.super_admin": ("SUPER_ADMIN_GIFT_DAILY_BUDGET_GEMS", 0),
    "gems.item_gift_max_qty": ("ADMIN_GIFT_MAX_ITEM_QTY", 1),
}
MAX_SETTING_VALUE = 1_000_000


def role_name(admin: User) -> str:
    return "super_admin" if admin.role_level >= 2 else "admin"


async def get_gem_limits(db: AsyncSession) -> dict[str, int]:
    rows = (
        await db.execute(select(AppSetting).where(AppSetting.key.in_(GEM_LIMIT_KEYS)))
    ).scalars().all()
    stored = {row.key: row.value for row in rows}
    return {
        key: int(stored[key]) if isinstance(stored.get(key), int) else int(getattr(settings, attr))
        for key, (attr, _) in GEM_LIMIT_KEYS.items()
    }


async def set_gem_limits(
    db: AsyncSession, admin: User, updates: dict[str, int]
) -> tuple[dict[str, int], dict[str, int]]:
    """Upsert changed keys; returns (before, after) of the changed keys only. Caller commits."""
    current = await get_gem_limits(db)
    before: dict[str, int] = {}
    after: dict[str, int] = {}
    for key, value in updates.items():
        if key not in GEM_LIMIT_KEYS:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, f"Unknown setting: {key}")
        floor = GEM_LIMIT_KEYS[key][1]
        if not floor <= value <= MAX_SETTING_VALUE:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY, f"{key} must be between {floor} and {MAX_SETTING_VALUE}"
            )
        if current[key] == value:
            continue
        before[key], after[key] = current[key], value
        row = await db.get(AppSetting, key)
        if row is None:
            db.add(AppSetting(key=key, value=value, updated_by=admin.id))
        else:
            row.value = value
            row.updated_by = admin.id
    return before, after


def utc_day_start(now: datetime | None = None) -> datetime:
    now = now or datetime.now(timezone.utc)
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


async def spent_today(db: AsyncSession, actor_id: UUID) -> int:
    total = (
        await db.execute(
            select(func.coalesce(func.sum(func.abs(AdminGemGrant.amount)), 0)).where(
                AdminGemGrant.actor_id == actor_id,
                AdminGemGrant.created_at >= utc_day_start(),
            )
        )
    ).scalar()
    return int(total or 0)


async def usage_for(db: AsyncSession, admin: User) -> dict[str, Any]:
    limits = await get_gem_limits(db)
    role = role_name(admin)
    budget = limits[f"gems.daily_budget.{role}"]
    spent = await spent_today(db, admin.id)
    return {
        "role": role,
        "max_per_action": limits[f"gems.gift_max_per_action.{role}"],
        "daily_budget": budget,
        "spent_today": spent,
        "remaining_today": max(budget - spent, 0),
        "item_gift_max_qty": limits["gems.item_gift_max_qty"],
    }


async def reserve_gems(
    db: AsyncSession, admin: User, user_id: UUID, kind: str, amount: int, reason: str
) -> None:
    """Check per-action cap and the day's budget, then queue the ledger row.

    The actor's row is locked first so two requests cannot both read the same
    "spent" figure. Raises 400 on any breach; the caller owns the commit.
    """
    await db.execute(select(User.id).where(User.id == admin.id).with_for_update())
    usage = await usage_for(db, admin)
    size = abs(amount)
    if size > usage["max_per_action"]:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"A single gem {kind} is limited to {usage['max_per_action']} for your role",
        )
    if size > usage["remaining_today"]:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Daily gem budget exceeded: {usage['remaining_today']} of {usage['daily_budget']} left today",
        )
    db.add(AdminGemGrant(actor_id=admin.id, user_id=user_id, kind=kind, amount=amount, reason=reason))
