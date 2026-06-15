"""Transactional XP mutation shared by API and game session completion."""

import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from typing import Awaitable, Callable

from fastapi import HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.games import XPTransaction
from app.models.gamification import LeaderboardEntry
from app.models.progress import DailyActivity, Streak
from app.models.user import User
from app.core.cache import invalidate_cache
from app.services.level_service import (
    check_numeric_level_up,
    get_numeric_level_progress,
)
from app.services.rank_service import apply_rank_info_to_user, calculate_rank


DAILY_XP_CAP = 500
MAX_SINGLE_AWARD = 200
STREAK_MULTIPLIERS = {3: 1.2, 7: 1.5, 30: 2.0}
XP_SOURCE_CAPS = {
    "game": 100,
    "news": 15,
    "youtube": 15,
    "podcast": 20,
    "book": 25,
    "lesson": 50,
    "daily_challenge": 50,
}
# Sources where the same activity must never be awarded twice.
# source_id is required for these to enforce idempotency via the DB partial unique index.
REPEAT_SENSITIVE_SOURCES: frozenset[str] = frozenset({"game", "lesson", "daily_challenge"})


@dataclass(frozen=True)
class XPAwardResult:
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

    def to_dict(self) -> dict:
        return asdict(self)


async def get_daily_xp(user_id: uuid.UUID, db: AsyncSession) -> int:
    today_start = datetime.now(timezone.utc).replace(
        hour=0,
        minute=0,
        second=0,
        microsecond=0,
    )
    result = await db.execute(
        select(func.coalesce(func.sum(XPTransaction.amount), 0)).where(
            XPTransaction.user_id == user_id,
            XPTransaction.created_at >= today_start,
        )
    )
    return int(result.scalar() or 0)


def calculate_streak_multiplier(streak_days: int) -> float:
    for threshold, multiplier in sorted(
        STREAK_MULTIPLIERS.items(),
        reverse=True,
    ):
        if streak_days >= threshold:
            return multiplier
    return 1.0


async def get_streak_days(user_id: uuid.UUID, db: AsyncSession) -> int:
    result = await db.execute(select(Streak).where(Streak.user_id == user_id))
    streak = result.scalar_one_or_none()
    if not streak or not streak.last_activity_date:
        return 0
    utc_today = datetime.now(timezone.utc).date()
    if (utc_today - streak.last_activity_date).days <= 1:
        return streak.current_streak
    return 0


async def award_xp_transaction(
    *,
    db: AsyncSession,
    user: User,
    source: str,
    base_xp: int,
    source_id: str | None = None,
    source_detail: str | None = None,
    commit: bool = True,
    daily_xp_loader: Callable[
        [uuid.UUID, AsyncSession], Awaitable[int]
    ] = get_daily_xp,
    streak_loader: Callable[
        [uuid.UUID, AsyncSession], Awaitable[int]
    ] = get_streak_days,
) -> XPAwardResult:
    if source not in XP_SOURCE_CAPS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported XP source: {source}",
        )
    if source in REPEAT_SENSITIVE_SOURCES and not source_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"source_id is required for source '{source}' to prevent duplicate awards.",
        )
    if base_xp < 0 or base_xp > MAX_SINGLE_AWARD:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid base XP amount.",
        )

    locked_user_result = await db.execute(
        select(User).where(User.id == user.id).with_for_update()
    )
    locked_user = locked_user_result.scalar_one_or_none() or user

    if source_id:
        existing = await db.execute(
            select(XPTransaction.id).where(
                XPTransaction.user_id == user.id,
                XPTransaction.source == source,
                XPTransaction.source_id == source_id,
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="XP already awarded for this activity.",
            )

    capped_base_xp = min(base_xp, XP_SOURCE_CAPS[source])
    streak_days = await streak_loader(user.id, db)
    multiplier = calculate_streak_multiplier(streak_days)
    raw_awarded = int(capped_base_xp * multiplier)
    daily_xp_today = await daily_xp_loader(user.id, db)
    cap_remaining = max(0, DAILY_XP_CAP - daily_xp_today)
    xp_awarded = min(raw_awarded, cap_remaining)

    old_xp = locked_user.total_xp or 0
    old_level = locked_user.numeric_level or 1
    if xp_awarded <= 0:
        progress = get_numeric_level_progress(old_xp)
        return XPAwardResult(
            xp_awarded=0,
            base_xp=capped_base_xp,
            multiplier=multiplier,
            new_total_xp=old_xp,
            daily_xp_today=daily_xp_today,
            daily_cap_remaining=0,
            leveled_up=False,
            old_level=old_level,
            new_level=old_level,
            current_xp_in_level=progress.current_xp_in_level,
            level_progress_percent=progress.level_progress_percent,
            xp_for_next_level=progress.xp_for_next_level,
            streak_days=streak_days,
            message="Daily XP cap (500) reached. Come back tomorrow!",
        )

    new_xp = old_xp + xp_awarded
    leveled_up, calculated_old_level, new_level = check_numeric_level_up(
        old_xp,
        new_xp,
    )
    rank_info = calculate_rank(new_level, locked_user.level or "A1")

    locked_user.total_xp = new_xp
    locked_user.numeric_level = new_level
    apply_rank_info_to_user(locked_user, rank_info)
    if locked_user is not user:
        user.total_xp = new_xp
        user.numeric_level = new_level
        apply_rank_info_to_user(user, rank_info)
    await db.execute(
        update(User)
        .where(User.id == user.id)
        .values(
            total_xp=new_xp,
            numeric_level=new_level,
            rank=rank_info.rank.value,
            rank_score=rank_info.score,
            rank_level_score=rank_info.level_score,
            rank_proficiency_score=rank_info.proficiency_score,
        )
    )

    db.add(
        XPTransaction(
            user_id=user.id,
            amount=xp_awarded,
            base_amount=capped_base_xp,
            multiplier=multiplier,
            source=source,
            source_id=source_id,
            source_detail=source_detail,
            level_before=calculated_old_level,
            level_after=new_level,
            leveled_up=leveled_up,
        )
    )

    utc_today = datetime.now(timezone.utc).date()
    result = await db.execute(
        select(DailyActivity).where(
            DailyActivity.user_id == user.id,
            DailyActivity.activity_date == utc_today,
        )
    )
    daily = result.scalar_one_or_none()
    if daily:
        daily.xp_earned = (daily.xp_earned or 0) + xp_awarded
    else:
        db.add(
            DailyActivity(
                user_id=user.id,
                activity_date=utc_today,
                xp_earned=xp_awarded,
            )
        )

    now = datetime.now(timezone.utc)
    week_start = (now - timedelta(days=now.weekday())).replace(
        hour=0,
        minute=0,
        second=0,
        microsecond=0,
    )
    leaderboard_result = await db.execute(
        select(LeaderboardEntry)
        .where(
            LeaderboardEntry.user_id == user.id,
            LeaderboardEntry.week_start == week_start,
        )
        .with_for_update()
    )
    leaderboard_entry = leaderboard_result.scalar_one_or_none()
    if leaderboard_entry:
        leaderboard_entry.xp_earned = (
            leaderboard_entry.xp_earned or 0
        ) + xp_awarded
        leaderboard_entry.league = rank_info.rank.value
    else:
        db.add(
            LeaderboardEntry(
                user_id=user.id,
                week_start=week_start,
                week_end=week_start + timedelta(days=7),
                league=rank_info.rank.value,
                xp_earned=xp_awarded,
            )
        )

    if commit:
        await db.commit()
        await invalidate_cache("leaderboard")

    progress = get_numeric_level_progress(new_xp)
    message = f"+{xp_awarded} XP earned!"
    if leveled_up:
        message = f"Level up! You reached level {new_level}! +{xp_awarded} XP"

    return XPAwardResult(
        xp_awarded=xp_awarded,
        base_xp=capped_base_xp,
        multiplier=multiplier,
        new_total_xp=new_xp,
        daily_xp_today=daily_xp_today + xp_awarded,
        daily_cap_remaining=max(0, cap_remaining - xp_awarded),
        leveled_up=leveled_up,
        old_level=calculated_old_level,
        new_level=new_level,
        current_xp_in_level=progress.current_xp_in_level,
        level_progress_percent=progress.level_progress_percent,
        xp_for_next_level=progress.xp_for_next_level,
        streak_days=streak_days,
        message=message,
    )


async def get_existing_xp_award(
    *,
    db: AsyncSession,
    user: User,
    source: str,
    source_id: str,
) -> XPAwardResult | None:
    transaction_result = await db.execute(
        select(XPTransaction).where(
            XPTransaction.user_id == user.id,
            XPTransaction.source == source,
            XPTransaction.source_id == source_id,
        )
    )
    transaction = transaction_result.scalar_one_or_none()
    if transaction is None:
        return None

    user_result = await db.execute(select(User).where(User.id == user.id))
    current_user = user_result.scalar_one_or_none() or user
    total_xp = current_user.total_xp or 0
    progress = get_numeric_level_progress(total_xp)
    daily_xp_today = await get_daily_xp(user.id, db)
    streak_days = await get_streak_days(user.id, db)

    return XPAwardResult(
        xp_awarded=transaction.amount,
        base_xp=transaction.base_amount,
        multiplier=transaction.multiplier or 1.0,
        new_total_xp=total_xp,
        daily_xp_today=daily_xp_today,
        daily_cap_remaining=max(0, DAILY_XP_CAP - daily_xp_today),
        leveled_up=bool(transaction.leveled_up),
        old_level=transaction.level_before or progress.numeric_level,
        new_level=transaction.level_after or progress.numeric_level,
        current_xp_in_level=progress.current_xp_in_level,
        level_progress_percent=progress.level_progress_percent,
        xp_for_next_level=progress.xp_for_next_level,
        streak_days=streak_days,
        message=f"+{transaction.amount} XP was already awarded.",
    )
