"""
XP API Routes — XP Award, Profile, and Leaderboard
Phase 3: English Games + XP System

Endpoints:
- POST /api/xp/award    — Validate and award XP with anti-cheat
- GET  /api/xp/profile  — User XP, level, streak, recent history
- GET  /api/xp/leaderboard — Weekly top users
"""

import logging
import uuid
from datetime import datetime, date, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select, func, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.progress import Streak, DailyActivity
from app.models.games import XPTransaction
from app.services.level_service import (
    get_numeric_level_progress,
    check_numeric_level_up,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/xp", tags=["XP System"])

# ── Constants ────────────────────────────────────────────────────────────────

DAILY_XP_CAP = 500          # Max XP per day (anti-grind)
MIN_GAME_DURATION = 5       # Minimum seconds for a valid game (anti-cheat)
MAX_SINGLE_AWARD = 200      # Max XP in a single award

# Streak bonus multipliers
STREAK_MULTIPLIERS = {
    3:  1.2,   # 3+ day streak → +20%
    7:  1.5,   # 7+ day streak → +50%
    30: 2.0,   # 30+ day streak → +100%
}

# XP per source (max per single award)
XP_SOURCE_CAPS = {
    "game":              100,
    "news":              15,
    "youtube":           15,
    "podcast":           20,
    "book":              25,
    "lesson":            50,
    "daily_challenge":   50,
}


# ── Request / Response Schemas ────────────────────────────────────────────────

class XPAwardRequest(BaseModel):
    source: str = Field(..., description="XP source: game|news|youtube|podcast|book|lesson")
    base_xp: int = Field(..., ge=1, le=200, description="Base XP before multipliers")
    source_id: Optional[str] = Field(None, description="ID of source (session UUID, article ID…)")
    source_detail: Optional[str] = Field(None, description="Human-readable detail (word_scramble)")
    duration_seconds: Optional[int] = Field(None, ge=0, description="Time spent (seconds)")
    score: Optional[int] = Field(None, description="Score if applicable (e.g. correct answers)")
    total_questions: Optional[int] = Field(None)


class XPAwardResponse(BaseModel):
    xp_awarded: int
    base_xp: int
    multiplier: float
    new_total_xp: int
    daily_xp_today: int
    daily_cap_remaining: int
    leveled_up: bool
    old_level: int
    new_level: int
    level_progress_percent: float
    xp_for_next_level: int
    streak_days: int
    message: str


class XPProfileResponse(BaseModel):
    user_id: str
    total_xp: int
    numeric_level: int
    level_progress_percent: float
    xp_for_next_level: int
    current_xp_in_level: int
    daily_xp_today: int
    daily_cap_remaining: int
    streak_days: int
    best_streak: int
    recent_transactions: list


# ── Helpers ──────────────────────────────────────────────────────────────────

async def _get_daily_xp(user_id: uuid.UUID, db: AsyncSession) -> int:
    """Get XP earned today for a user from XPTransaction log."""
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    result = await db.execute(
        select(func.coalesce(func.sum(XPTransaction.amount), 0))
        .where(
            XPTransaction.user_id == user_id,
            XPTransaction.created_at >= today_start,
        )
    )
    return int(result.scalar() or 0)


def _calculate_streak_multiplier(streak_days: int) -> float:
    """Return streak multiplier based on consecutive days."""
    multiplier = 1.0
    for threshold, mult in sorted(STREAK_MULTIPLIERS.items(), reverse=True):
        if streak_days >= threshold:
            multiplier = mult
            break
    return multiplier


async def _get_streak_days(user_id: uuid.UUID, db: AsyncSession) -> int:
    """Get current streak days for a user."""
    result = await db.execute(
        select(Streak).where(Streak.user_id == user_id)
    )
    streak_obj = result.scalar_one_or_none()
    if not streak_obj:
        return 0
    # Check if streak is still active (last activity was today or yesterday)
    if streak_obj.last_activity_date:
        delta = date.today() - streak_obj.last_activity_date
        if delta.days <= 1:
            return streak_obj.current_streak
    return 0


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/award", response_model=XPAwardResponse)
async def award_xp(
    body: XPAwardRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Award XP to the current user.

    Anti-cheat checks:
    - Duration must be ≥ MIN_GAME_DURATION seconds (for game sources)
    - XP capped per source type
    - Daily XP cap: 500 XP/day
    - Duplicate source_id prevention (same session can't earn twice)

    Streak bonus:
    - 3+ days → 1.2× multiplier
    - 7+ days → 1.5× multiplier
    - 30+ days → 2.0× multiplier
    """
    user_id = current_user.id

    # ── 1. Anti-cheat: duration check for game sources ──────────────────────
    if body.source == "game" and body.duration_seconds is not None:
        if body.duration_seconds < MIN_GAME_DURATION:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Game too short — possible cheating detected.",
            )

    # ── 2. Anti-cheat: duplicate source_id check ────────────────────────────
    if body.source_id:
        existing = await db.execute(
            select(XPTransaction).where(
                XPTransaction.user_id == user_id,
                XPTransaction.source_id == body.source_id,
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="XP already awarded for this activity.",
            )

    # ── 3. Cap base XP per source ────────────────────────────────────────────
    source_cap = XP_SOURCE_CAPS.get(body.source, 50)
    base_xp = min(body.base_xp, source_cap)

    # ── 4. Apply streak multiplier ────────────────────────────────────────────
    streak_days = await _get_streak_days(user_id, db)
    multiplier = _calculate_streak_multiplier(streak_days)
    raw_awarded = int(base_xp * multiplier)

    # ── 5. Daily XP cap ──────────────────────────────────────────────────────
    daily_xp_today = await _get_daily_xp(user_id, db)
    cap_remaining = max(0, DAILY_XP_CAP - daily_xp_today)
    xp_awarded = min(raw_awarded, cap_remaining)

    if xp_awarded <= 0:
        # Daily cap reached
        return XPAwardResponse(
            xp_awarded=0,
            base_xp=base_xp,
            multiplier=multiplier,
            new_total_xp=current_user.total_xp,
            daily_xp_today=daily_xp_today,
            daily_cap_remaining=0,
            leveled_up=False,
            old_level=current_user.numeric_level,
            new_level=current_user.numeric_level,
            level_progress_percent=0.0,
            xp_for_next_level=0,
            streak_days=streak_days,
            message="Daily XP cap (500) reached. Come back tomorrow!",
        )

    # ── 6. Check level up BEFORE applying XP ─────────────────────────────────
    old_xp = current_user.total_xp or 0
    new_xp = old_xp + xp_awarded
    leveled_up, old_level, new_level = check_numeric_level_up(old_xp, new_xp)

    # ── 7. Update User.total_xp and numeric_level ────────────────────────────
    await db.execute(
        update(User)
        .where(User.id == user_id)
        .values(
            total_xp=new_xp,
            numeric_level=new_level,
        )
    )

    # ── 8. Record XPTransaction ───────────────────────────────────────────────
    tx = XPTransaction(
        user_id=user_id,
        amount=xp_awarded,
        base_amount=base_xp,
        multiplier=multiplier,
        source=body.source,
        source_id=body.source_id,
        source_detail=body.source_detail,
        level_before=old_level,
        level_after=new_level,
        leveled_up=leveled_up,
    )
    db.add(tx)

    # ── 9. Update DailyActivity ───────────────────────────────────────────────
    today = date.today()
    result = await db.execute(
        select(DailyActivity).where(
            DailyActivity.user_id == user_id,
            DailyActivity.activity_date == today,
        )
    )
    daily = result.scalar_one_or_none()
    if daily:
        await db.execute(
            update(DailyActivity)
            .where(DailyActivity.user_id == user_id, DailyActivity.activity_date == today)
            .values(xp_earned=DailyActivity.xp_earned + xp_awarded)
        )
    else:
        db.add(DailyActivity(user_id=user_id, activity_date=today, xp_earned=xp_awarded))

    await db.commit()

    # ── 10. Build response ────────────────────────────────────────────────────
    level_info = get_numeric_level_progress(new_xp)

    logger.info(
        f"XP awarded: user={user_id} source={body.source} +{xp_awarded} XP "
        f"(base={base_xp}×{multiplier:.1f}) total={new_xp} level={new_level}"
    )

    message = f"+{xp_awarded} XP earned!"
    if leveled_up:
        message = f"Level up! You reached level {new_level}! +{xp_awarded} XP"

    return XPAwardResponse(
        xp_awarded=xp_awarded,
        base_xp=base_xp,
        multiplier=multiplier,
        new_total_xp=new_xp,
        daily_xp_today=daily_xp_today + xp_awarded,
        daily_cap_remaining=max(0, cap_remaining - xp_awarded),
        leveled_up=leveled_up,
        old_level=old_level,
        new_level=new_level,
        level_progress_percent=level_info.level_progress_percent,
        xp_for_next_level=level_info.xp_for_next_level,
        streak_days=streak_days,
        message=message,
    )


@router.get("/profile", response_model=XPProfileResponse)
async def get_xp_profile(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get detailed XP profile for the current user.
    Includes level progress, daily status, streak, and recent transaction history.
    """
    user_id = current_user.id
    total_xp = current_user.total_xp or 0

    level_info = get_numeric_level_progress(total_xp)
    daily_xp = await _get_daily_xp(user_id, db)
    streak_days = await _get_streak_days(user_id, db)

    # Best streak
    streak_result = await db.execute(
        select(Streak).where(Streak.user_id == user_id)
    )
    streak_obj = streak_result.scalar_one_or_none()
    best_streak = streak_obj.longest_streak if streak_obj else 0

    # Recent XP transactions (last 20)
    tx_result = await db.execute(
        select(XPTransaction)
        .where(XPTransaction.user_id == user_id)
        .order_by(XPTransaction.created_at.desc())
        .limit(20)
    )
    transactions = tx_result.scalars().all()
    recent = [
        {
            "id": str(t.id),
            "amount": t.amount,
            "source": t.source,
            "source_detail": t.source_detail,
            "leveled_up": t.leveled_up,
            "created_at": t.created_at.isoformat(),
        }
        for t in transactions
    ]

    return XPProfileResponse(
        user_id=str(user_id),
        total_xp=total_xp,
        numeric_level=level_info.numeric_level,
        level_progress_percent=level_info.level_progress_percent,
        xp_for_next_level=level_info.xp_for_next_level,
        current_xp_in_level=level_info.current_xp_in_level,
        daily_xp_today=daily_xp,
        daily_cap_remaining=max(0, DAILY_XP_CAP - daily_xp),
        streak_days=streak_days,
        best_streak=best_streak,
        recent_transactions=recent,
    )


@router.get("/leaderboard")
async def get_leaderboard(
    limit: int = Query(20, ge=1, le=100, description="Max entries to return"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get weekly XP leaderboard — top users by XP earned this week.
    Also returns current user's rank.
    """
    week_start = datetime.now(timezone.utc) - timedelta(days=datetime.now(timezone.utc).weekday())
    week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)

    # Weekly XP per user
    weekly_subq = (
        select(
            XPTransaction.user_id,
            func.sum(XPTransaction.amount).label("weekly_xp"),
        )
        .where(XPTransaction.created_at >= week_start)
        .group_by(XPTransaction.user_id)
        .subquery()
    )

    # Join with users table
    result = await db.execute(
        select(User, weekly_subq.c.weekly_xp)
        .outerjoin(weekly_subq, User.id == weekly_subq.c.user_id)
        .order_by((weekly_subq.c.weekly_xp).desc().nullslast())
        .limit(limit)
    )
    rows = result.all()

    entries = []
    for rank, (user, weekly_xp) in enumerate(rows, start=1):
        entries.append(
            {
                "rank": rank,
                "user_id": str(user.id),
                "username": user.username,
                "total_xp": user.total_xp or 0,
                "numeric_level": user.numeric_level or 1,
                "weekly_xp": weekly_xp or 0,
            }
        )

    # Current user's rank (if not in top N)
    user_rank = None
    current_weekly = await db.execute(
        select(func.coalesce(func.sum(XPTransaction.amount), 0))
        .where(
            XPTransaction.user_id == current_user.id,
            XPTransaction.created_at >= week_start,
        )
    )
    current_weekly_xp = int(current_weekly.scalar() or 0)

    rank_count = await db.execute(
        select(func.count())
        .select_from(
            select(
                XPTransaction.user_id,
                func.sum(XPTransaction.amount).label("wk"),
            )
            .where(XPTransaction.created_at >= week_start)
            .group_by(XPTransaction.user_id)
            .having(func.sum(XPTransaction.amount) > current_weekly_xp)
            .subquery()
        )
    )
    user_rank = int(rank_count.scalar() or 0) + 1

    return {
        "entries": entries,
        "current_user": {
            "user_id": str(current_user.id),
            "username": current_user.username,
            "total_xp": current_user.total_xp or 0,
            "numeric_level": current_user.numeric_level or 1,
            "weekly_xp": current_weekly_xp,
            "rank": user_rank,
        },
        "week_start": week_start.isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
