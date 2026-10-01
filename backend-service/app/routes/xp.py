"""
XP API Routes — XP Award, Profile, and Leaderboard
Phase 3: English Games + XP System

Endpoints:
- POST /api/xp/award    — Validate and award XP with anti-cheat
- GET  /api/xp/profile  — User XP, level, streak, recent history
- GET  /api/xp/leaderboard — Weekly top users
"""

import uuid
from datetime import datetime, date, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.progress import Streak
from app.models.games import XPTransaction
from app.services.level_service import get_numeric_level_progress
from app.services.xp_service import (
    MAX_STUDY_MINUTES_PER_AWARD,
    award_xp_transaction,
    capped_duration_seconds,
)
from app.crud.leaderboard import competition_ranks

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
    current_xp_in_level: int
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
    if body.source == "game":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Game XP must be awarded through a completed game session.",
        )

    result = await award_xp_transaction(
        db=db,
        user=current_user,
        source=body.source,
        base_xp=body.base_xp,
        source_id=body.source_id,
        source_detail=body.source_detail,
        duration_seconds=body.duration_seconds,
        daily_xp_loader=_get_daily_xp,
        streak_loader=_get_streak_days,
    )
    return XPAwardResponse(**result.to_dict())


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
            "duration_seconds": t.duration_seconds,
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


# Which content sources report how long the learner spent.
#
# All four do now. Reading was the last gap: the article screen and the reader
# report time the same way the players do, counting only while the learner is in
# the foreground and something happened recently (`ContentTimeTracker` on the
# client). A source left at False here would have its real minutes hidden by the
# UI, so this must follow what the clients actually send.
CONTENT_SOURCE_TRACKS_MINUTES: dict[str, bool] = {
    "youtube": True,
    "podcast": True,
    "news": True,
    "book": True,
}
CONTENT_SOURCES: tuple[str, ...] = tuple(CONTENT_SOURCE_TRACKS_MINUTES)


class ContentSourceActivity(BaseModel):
    source: str
    sessions: int = Field(..., description="Awarded activities in the window")
    minutes: int = Field(..., description="Reported time, capped per activity")
    tracks_minutes: bool = Field(
        ...,
        description="False means this source is credited per activity, not by time",
    )
    xp_earned: int
    last_active_at: Optional[str] = None


class ContentActivityResponse(BaseModel):
    days: int
    since: str
    total_minutes: int
    total_sessions: int
    total_xp: int
    by_source: list[ContentSourceActivity]


@router.get("/content-activity", response_model=ContentActivityResponse)
async def get_content_activity(
    days: int = Query(7, ge=1, le=90),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """What this learner got credited for on the library/podcast/video/news surfaces.

    Read straight off `XPTransaction`, the immutable row each award already
    writes — so what a learner is shown here is exactly what the system counted,
    and a missing entry is evidence the activity never registered rather than a
    reporting gap. Every content source is listed even at zero, so "nothing was
    recorded" is visible instead of absent.

    `minutes` applies the same per-activity ceiling the daily quests use: the
    duration is reported by the client and nothing verifies it.
    """
    since = datetime.now(timezone.utc) - timedelta(days=days)
    capped_seconds = capped_duration_seconds()

    result = await db.execute(
        select(
            XPTransaction.source,
            func.count(XPTransaction.id),
            func.coalesce(func.sum(capped_seconds), 0),
            func.coalesce(func.sum(XPTransaction.amount), 0),
            func.max(XPTransaction.created_at),
        )
        .where(
            XPTransaction.user_id == current_user.id,
            XPTransaction.source.in_(CONTENT_SOURCES),
            XPTransaction.created_at >= since,
        )
        .group_by(XPTransaction.source)
    )
    rows = {
        source: (sessions, seconds, xp, last)
        for source, sessions, seconds, xp, last in result.all()
    }

    by_source = [
        ContentSourceActivity(
            source=source,
            sessions=rows.get(source, (0, 0, 0, None))[0],
            minutes=int(rows.get(source, (0, 0, 0, None))[1] or 0) // 60,
            tracks_minutes=CONTENT_SOURCE_TRACKS_MINUTES[source],
            xp_earned=int(rows.get(source, (0, 0, 0, None))[2] or 0),
            last_active_at=(
                rows[source][3].isoformat()
                if source in rows and rows[source][3] is not None
                else None
            ),
        )
        for source in CONTENT_SOURCES
    ]

    return ContentActivityResponse(
        days=days,
        since=since.isoformat(),
        total_minutes=sum(s.minutes for s in by_source),
        total_sessions=sum(s.sessions for s in by_source),
        total_xp=sum(s.xp_earned for s in by_source),
        by_source=by_source,
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

    weekly_scores = [int(weekly_xp or 0) for _, weekly_xp in rows]
    ranks = competition_ranks(weekly_scores)
    entries = []
    for rank, (user, weekly_xp) in zip(ranks, rows):
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
        "scope": "overall",
    }
