import logging
from datetime import date, datetime, timedelta, timezone
from uuid import UUID
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import LeaderboardEntry
from app.models.progress import Streak, DailyActivity
from app.core.cache import build_cache_key, delete_cached
from app.services import check_achievements_for_user

logger = logging.getLogger(__name__)


def _utc_today() -> date:
    return datetime.now(timezone.utc).date()

async def get_or_create_daily_activity(
    db: AsyncSession, user_id: UUID, today: date | None = None
) -> DailyActivity:
    """Today's DailyActivity row for this user, staged if it did not exist.

    Production sessions disable autoflush, so another service in the same
    request may already have staged today's row without making it visible to a
    SELECT — check `db.new` before querying, or two rows race for the same day.
    """
    today = today or _utc_today()
    staged = next(
        (
            row
            for row in db.new
            if isinstance(row, DailyActivity)
            and row.user_id == user_id
            and row.activity_date == today
        ),
        None,
    )
    if staged is not None:
        return staged

    result = await db.execute(
        select(DailyActivity).where(
            and_(
                DailyActivity.user_id == user_id,
                DailyActivity.activity_date == today,
            )
        )
    )
    existing = result.scalar_one_or_none()
    if existing is not None:
        return existing

    created = DailyActivity(
        user_id=user_id,
        activity_date=today,
        xp_earned=0,
        lessons_completed=0,
        study_time_minutes=0,
        vocabulary_reviewed=0,
    )
    db.add(created)
    return created


async def record_weekly_leaderboard_xp(
    db: AsyncSession, user_id: UUID, xp: int, *, league: str | None = None
) -> None:
    """Add XP to this user's entry for the current week. Never commits.

    Monday-based week, matching `LeaderboardCRUD.get_current_week_range` — the
    two must agree or a learner gets two rows for one week.

    Callers must not commit on our behalf: lesson completion and challenge
    claims hold a row lock and finish their own transaction.
    """
    if xp <= 0:
        return

    now = datetime.now(timezone.utc)
    week_start = (now - timedelta(days=now.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    staged = next(
        (
            row
            for row in db.new
            if isinstance(row, LeaderboardEntry)
            and row.user_id == user_id
            and row.week_start == week_start
        ),
        None,
    )
    if staged is not None:
        staged.xp_earned = (staged.xp_earned or 0) + xp
        if league:
            staged.league = league
        return

    result = await db.execute(
        select(LeaderboardEntry)
        .where(
            LeaderboardEntry.user_id == user_id,
            LeaderboardEntry.week_start == week_start,
        )
        .with_for_update()
    )
    entry = result.scalar_one_or_none()
    if entry is not None:
        entry.xp_earned = (entry.xp_earned or 0) + xp
        if league:
            entry.league = league
        return

    db.add(
        LeaderboardEntry(
            user_id=user_id,
            week_start=week_start,
            week_end=week_start + timedelta(days=7),
            league=league or "bronze",
            xp_earned=xp,
        )
    )


async def record_daily_activity(
    db: AsyncSession,
    user_id: UUID,
    *,
    xp_earned: int = 0,
    lessons_completed: int = 0,
    study_time_minutes: int = 0,
    vocabulary_reviewed: int = 0,
    league: str | None = None,
    today: date | None = None,
) -> DailyActivity:
    """Add a finished activity to today's totals and this week's leaderboard.

    Every counter is additive, so callers pass what just happened rather than a
    running total. `study_time_minutes` in particular was written only ever as
    0 by every creator of this row, which is why the progress page reported
    zero study time however much anyone practised — pass the real duration.

    `xp_earned` also goes to the weekly leaderboard, because only 2 of the 8
    places that raised `User.total_xp` updated it: a learner who did lessons and
    vocabulary ranked below anyone who had played one game, however much XP
    their profile showed. Call this instead of touching either row by hand.
    """
    daily = await get_or_create_daily_activity(db, user_id, today)
    daily.xp_earned = (daily.xp_earned or 0) + xp_earned
    daily.lessons_completed = (daily.lessons_completed or 0) + lessons_completed
    daily.study_time_minutes = (daily.study_time_minutes or 0) + study_time_minutes
    daily.vocabulary_reviewed = (daily.vocabulary_reviewed or 0) + vocabulary_reviewed
    if daily.xp_earned >= (daily.daily_goal_xp or 0):
        daily.daily_goal_met = True
    db.add(daily)
    await record_weekly_leaderboard_xp(db, user_id, xp_earned, league=league)
    return daily


async def update_user_streak(db: AsyncSession, user_id: UUID) -> tuple[Streak, bool, bool, list]:
    """
    Unified function to update user's streak.
    Handles:
    - Creating streak record if first time
    - Incrementing streak for consecutive days
    - Using streak freeze if available when a gap is 1 day
    - Resetting streak if gap > 1 day, saving current streak to previous_streak
    - Ensuring DailyActivity record exists
    - Checking streak-based achievements
    - Invalidating redis cache
    
    Returns:
    - (streak, streak_increased, streak_saved, unlocked_achievements)
    """
    result = await db.execute(
        select(Streak).where(Streak.user_id == user_id).with_for_update()
    )
    streak = result.scalar_one_or_none()
    
    today = _utc_today()
    streak_increased = False
    streak_saved = False
    
    if not streak:
        # Create new streak
        streak = Streak(
            user_id=user_id,
            current_streak=1,
            longest_streak=1,
            last_activity_date=today,
            total_days_active=1,
            freeze_count=0,
            previous_streak=0,
            restores_used_this_month=0
        )
        db.add(streak)
        streak_increased = True
    else:
        last_date = streak.last_activity_date
        
        if last_date == today:
            # Already active today, no change
            pass
        elif last_date == today - timedelta(days=1):
            # Consecutive day - increment streak
            streak.current_streak += 1
            streak.total_days_active += 1
            streak.last_activity_date = today
            streak_increased = True
            
            if streak.current_streak > streak.longest_streak:
                streak.longest_streak = streak.current_streak
        elif last_date and last_date < today - timedelta(days=1):
            # Gap in activity
            days_missed = (today - last_date).days - 1
            
            if getattr(streak, 'freeze_count', 0) > 0 and days_missed == 1:
                # Use freeze to save streak
                streak.freeze_count -= 1
                streak.current_streak += 1
                streak.total_days_active += 1
                streak.last_activity_date = today
                streak_saved = True
                streak_increased = True
                
                if streak.current_streak > streak.longest_streak:
                    streak.longest_streak = streak.current_streak
            else:
                # Reset streak: save current streak to previous_streak before resetting
                streak.previous_streak = streak.current_streak
                streak.current_streak = 1
                streak.total_days_active += 1
                streak.last_activity_date = today
                streak_increased = True
        else:
            # First activity ever
            streak.current_streak = 1
            streak.total_days_active = 1
            streak.last_activity_date = today
            streak_increased = True
            
            if streak.current_streak > streak.longest_streak:
                streak.longest_streak = streak.current_streak
                
    # Ensure a DailyActivity record exists for today so weekly_activity is accurate
    daily_activity = await get_or_create_daily_activity(db, user_id, today)

    await db.flush() # flush to DB before check_achievements
    
    # Check streak-based achievements
    unlocked_achievements = []
    try:
        unlocked_achievements = await check_achievements_for_user(
            db, user_id, "streak_update"
        )
    except Exception as e:
        logger.error("Achievement check error: %s", e, exc_info=True)

    # Invalidate caches
    uid_str = str(user_id)
    await delete_cached(build_cache_key("progress_streak", user_id=uid_str))
    await delete_cached(build_cache_key("progress_me", user_id=uid_str))

    return streak, streak_increased, streak_saved, unlocked_achievements
