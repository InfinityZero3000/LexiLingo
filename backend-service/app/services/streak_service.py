import logging
from datetime import date, datetime, timedelta, timezone
from uuid import UUID
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.progress import Streak, DailyActivity
from app.core.cache import build_cache_key, delete_cached
from app.services import check_achievements_for_user

logger = logging.getLogger(__name__)


def _utc_today() -> date:
    return datetime.now(timezone.utc).date()

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
        select(Streak).where(Streak.user_id == user_id)
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
    daily_result = await db.execute(
        select(DailyActivity).where(
            and_(
                DailyActivity.user_id == user_id,
                DailyActivity.activity_date == today,
            )
        )
    )
    daily_activity = daily_result.scalar_one_or_none()
    if not daily_activity:
        daily_activity = DailyActivity(
            user_id=user_id,
            activity_date=today,
            xp_earned=0,
            lessons_completed=0,
            study_time_minutes=0,
            vocabulary_reviewed=0,
        )
        db.add(daily_activity)

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
