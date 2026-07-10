"""
Progress Routes
API endpoints for tracking user progress

Following agent-skills/language-learning-patterns:
- progress-learning-streaks: Robust streak system with protections (3-5x engagement)
- gamification-achievement-badges: Meaningful achievements (25-40% engagement boost)
"""
from datetime import date, datetime, timedelta
import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.core.cache import (
    build_cache_key,
    compute_cache_version,
    delete_cached,
    get_cached,
    set_cached,
)
from app.crud.progress import ProgressCRUD
from app.crud.course import CourseCRUD
from app.schemas.progress import (
    LessonCompletionCreate,
    LessonCompletionResponse,
    UserProgressSummary,
    CourseProgressResponse,
    ProgressStatsResponse
)
from app.schemas.response import ApiResponse
from app.models.user import User
from app.models.progress import Streak, DailyActivity, LessonCompletion
from app.models.course import Lesson, Unit
from app.services import check_achievements_for_user
from app.services.level_service import (
    LevelService, calculate_numeric_level, get_numeric_level_progress,
    check_numeric_level_up
)
from app.services.rank_service import (
    apply_rank_info_to_user,
    calculate_rank as calc_rank,
    check_rank_up,
)
from app.services.streak_service import update_user_streak
from app.crud.gamification import WalletCRUD

router = APIRouter(prefix="/progress", tags=["Progress"])
logger = logging.getLogger(__name__)


@router.get("/me", response_model=ApiResponse[ProgressStatsResponse])
async def get_my_progress(
    response: Response,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's overall progress statistics
    
    Returns:
    - Summary: Total XP, courses enrolled/completed, lessons completed
    - Recent activity: Last 7 days of activity
    - Course progress: Progress for all enrolled courses
    """
    uid = str(current_user.id)
    cache_key = build_cache_key("progress_me", user_id=uid)
    cached = await get_cached(cache_key)
    if cached is not None:
        response.headers["X-Cache-Version"] = compute_cache_version(cached)
        response.headers["X-Cache-Source"] = "redis"
        return ApiResponse(success=True, message="Progress retrieved successfully", data=cached)

    # Get user stats
    stats = await ProgressCRUD.get_user_stats(db, uid)
    
    # Get progress with course data in a single JOIN query (no N+1)
    rows = await ProgressCRUD.get_user_progress_with_courses(
        db, uid, limit=10
    )

    # Fetch accurate lessons_completed counts from lesson_completions in one query
    course_ids = [str(course.id) for _, course in rows]
    lesson_counts: dict[str, int] = {}
    if course_ids:
        lc_result = await db.execute(
            select(Unit.course_id, func.count(LessonCompletion.id).label("cnt"))
            .join(Lesson, Lesson.id == LessonCompletion.lesson_id)
            .join(Unit, Unit.id == Lesson.unit_id)
            .where(
                and_(
                    LessonCompletion.user_id == uid,
                    LessonCompletion.is_passed == True,
                    Unit.course_id.in_(course_ids),
                )
            )
            .group_by(Unit.course_id)
        )
        lesson_counts = {str(row.course_id): row.cnt for row in lc_result.all()}

    course_progress_list = []
    for progress, course in rows:
        course_progress_list.append({
            'course_id': str(course.id),
            'course_title': course.title,
            'progress_percentage': progress.progress_percentage,
            'lessons_completed': lesson_counts.get(str(course.id), 0),
            'total_lessons': course.total_lessons or 0,
            'total_xp_earned': progress.total_xp_earned,
            'started_at': progress.started_at,
            'last_activity_at': progress.last_activity_at,
        })
    
    seven_days_ago = date.today() - timedelta(days=7)
    activity_rows = await db.execute(
        select(DailyActivity)
        .where(
            and_(
                DailyActivity.user_id == uid,
                DailyActivity.activity_date >= seven_days_ago,
            )
        )
        .order_by(DailyActivity.activity_date.desc())
    )
    recent_activity = [
        {
            "date": str(row.activity_date),
            "xp_earned": row.xp_earned,
            "lessons_completed": row.lessons_completed,
            "time_spent_minutes": row.study_time_minutes,
            "daily_goal_met": row.daily_goal_met,
        }
        for row in activity_rows.scalars().all()
    ]

    response_data = {
        'summary': stats,
        'recent_activity': recent_activity,
        'course_progress': course_progress_list
    }

    await set_cached(cache_key, response_data, ttl=30)
    response.headers["X-Cache-Version"] = compute_cache_version(response_data)
    response.headers["X-Cache-Source"] = "origin"

    return ApiResponse(
        success=True,
        message="Progress retrieved successfully",
        data=response_data
    )


@router.get("/courses/{course_id}", response_model=ApiResponse[CourseProgressResponse])
async def get_course_progress(
    course_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get detailed progress for a specific course
    
    Returns:
    - Course overview with progress percentage
    - Unit-by-unit progress breakdown
    - Lessons completed per unit
    """
    # Check if course exists
    course = await CourseCRUD.get_course(db, course_id)
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Course {course_id} not found"
        )
    
    # Check if user is enrolled
    is_enrolled = await CourseCRUD.is_user_enrolled(db, str(current_user.id), course_id)
    if not is_enrolled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not enrolled in this course"
        )
    
    # Get detailed progress
    progress_detail = await ProgressCRUD.get_course_progress_detail(
        db, str(current_user.id), course_id
    )
    
    if not progress_detail:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Progress not found for this course"
        )
    
    return ApiResponse(
        success=True,
        message="Course progress retrieved successfully",
        data=progress_detail
    )


@router.post("/lessons/{lesson_id}/complete", response_model=ApiResponse[LessonCompletionResponse])
async def complete_lesson(
    lesson_id: str,
    completion: LessonCompletionCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Mark a lesson as complete with a score
    
    Requirements:
    - User must be enrolled in the course
    - Score must be between 0-100
    
    Logic:
    - If score >= pass_threshold (80%): Mark as passed, award XP
    - If already completed: Update only if new score is better
    - Updates course progress percentage automatically
    
    Returns:
    - Lesson completion details
    - XP earned (if passed)
    - Updated course progress
    """
    try:
        # Get lesson and verify it exists
        from app.crud.course import LessonCRUD
        lesson = await LessonCRUD.get_lesson(db, lesson_id)
        if not lesson:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Lesson {lesson_id} not found"
            )
        
        # Get unit to find course_id
        from app.crud.course import UnitCRUD
        unit = await UnitCRUD.get_unit(db, str(lesson.unit_id))
        if not unit:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Unit not found for this lesson"
            )
        
        course_id = str(unit.course_id)
        
        # Check if user is enrolled
        is_enrolled = await CourseCRUD.is_user_enrolled(db, str(current_user.id), course_id)
        if not is_enrolled:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You must be enrolled in the course to complete lessons"
            )
        
        # Mark lesson complete
        lesson_completion, xp_earned = await ProgressCRUD.mark_lesson_complete(
            db,
            str(current_user.id),
            lesson_id,
            completion.score,
            lesson.pass_threshold or 80.0
        )
        
        # Recalculate course progress
        new_progress = await ProgressCRUD.calculate_course_progress(
            db, str(current_user.id), course_id
        )
        
        # Update course progress
        course_progress = await ProgressCRUD.update_course_progress(
            db,
            str(current_user.id),
            course_id,
            new_progress,
            xp_earned
        )
        
        # --- Update User.total_xp and numeric_level ---
        level_up = False
        new_level = None
        rank_up = False
        new_rank = None
        
        if xp_earned > 0:
            old_xp = current_user.total_xp or 0
            old_numeric_level = current_user.numeric_level or 1
            old_proficiency = current_user.level or "A1"
            
            new_xp = old_xp + xp_earned
            current_user.total_xp = new_xp
            
            # Update numeric level
            new_numeric_level = calculate_numeric_level(new_xp)
            current_user.numeric_level = new_numeric_level
            
            # Check CEFR tier change
            tier_up, _ = LevelService.check_level_up(old_xp, new_xp)
            if tier_up:
                cefr_status = LevelService.calculate_level_status(new_xp)
                current_user.level = cefr_status.current_tier.code
            
            # Check numeric level up
            leveled, _, _ = check_numeric_level_up(old_xp, new_xp)
            if leveled:
                level_up = True
                new_level = new_numeric_level
            
            # Check rank change
            new_rank_info = calc_rank(new_numeric_level, current_user.level)
            if current_user.rank != new_rank_info.rank.value:
                rank_up = True
                new_rank = new_rank_info.rank.value
            apply_rank_info_to_user(current_user, new_rank_info)
            
            # --- Update DailyActivity ---
            from datetime import date as date_type
            today = date_type.today()
            daily_result = await db.execute(
                select(DailyActivity).where(
                    and_(
                        DailyActivity.user_id == current_user.id,
                        DailyActivity.activity_date == today,
                    )
                )
            )
            daily_activity = daily_result.scalar_one_or_none()
            
            if daily_activity:
                daily_activity.xp_earned = (daily_activity.xp_earned or 0) + xp_earned
                daily_activity.lessons_completed = (daily_activity.lessons_completed or 0) + 1
            else:
                daily_activity = DailyActivity(
                    user_id=current_user.id,
                    activity_date=today,
                    xp_earned=xp_earned,
                    lessons_completed=1,
                )
                db.add(daily_activity)
        
        await db.commit()
        
        # --- Check achievements after lesson completion ---
        unlocked_from_lesson = await check_achievements_for_user(
            db, current_user.id, "lesson_complete"
        )
        unlocked_from_xp = await check_achievements_for_user(
            db, current_user.id, "xp_earned"
        )
        all_unlocked = unlocked_from_lesson + unlocked_from_xp
        if completion.score >= 100:
            perfect_unlocked = await check_achievements_for_user(
                db, current_user.id, "quiz_complete"
            )
            all_unlocked += perfect_unlocked
        
        # Get user's total XP
        total_xp = current_user.total_xp
        
        message = "Lesson completed successfully"
        if xp_earned > 0:
            message += f" - Earned {xp_earned} XP!"
        elif lesson_completion.is_passed:
            message += " - Already passed, no additional XP"
        else:
            message += f" - Score too low (need {lesson.pass_threshold or 80}% to pass)"
        
        response_data = {
            'lesson_id': lesson_id,
            'is_passed': lesson_completion.is_passed,
            'score': completion.score,
            'best_score': lesson_completion.best_score,
            'xp_earned': xp_earned,
            'total_xp': total_xp,
            'course_progress': new_progress,
            'level_up': level_up,
            'new_level': new_level,
            'rank_up': rank_up,
            'new_rank': new_rank,
            'achievements_unlocked': all_unlocked,
            'message': message
        }

        # Invalidate user's progress caches since XP/lessons changed
        _uid = str(current_user.id)
        await delete_cached(build_cache_key("progress_me", user_id=_uid))
        await delete_cached(build_cache_key("progress_xp", user_id=_uid))

        return ApiResponse(
            success=True,
            message=message,
            data=response_data
        )
        
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error completing lesson: {str(e)}"
        )


@router.get("/xp", response_model=ApiResponse[dict])
async def get_total_xp(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get user's total XP across all courses
    
    Returns:
    - total_xp: Sum of XP from all courses
    """
    uid = str(current_user.id)
    cache_key = build_cache_key("progress_xp", user_id=uid)
    cached = await get_cached(cache_key)
    if cached is not None:
        return ApiResponse(success=True, message="Total XP retrieved successfully", data=cached)

    total_xp = await ProgressCRUD.get_user_total_xp(db, uid)
    payload = {'total_xp': total_xp}
    await set_cached(cache_key, payload, ttl=30)

    return ApiResponse(
        success=True,
        message="Total XP retrieved successfully",
        data=payload
    )


# ============================================================================
# Weekly Progress Endpoints (Task 1.3)
# ============================================================================

@router.get("/weekly", response_model=ApiResponse[dict])
async def get_weekly_progress(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get user's weekly progress for the last 7 days
    
    Returns:
    - days: List of daily activity data for last 7 days
    - total_xp: Total XP earned this week
    - average_xp: Average XP per day
    - best_day: Day with highest XP
    
    Used for weekly progress visualization in Flutter app.
    """
    today = date.today()
    week_start = today - timedelta(days=6)  # Last 7 days including today
    
    # Query daily activities for the week
    result = await db.execute(
        select(DailyActivity)
        .where(
            and_(
                DailyActivity.user_id == current_user.id,
                DailyActivity.activity_date >= week_start,
                DailyActivity.activity_date <= today
            )
        )
        .order_by(DailyActivity.activity_date)
    )
    activities = result.scalars().all()

    # Aggregate weekly totals directly from DB records (missing days = 0)
    total_lessons = sum(a.lessons_completed for a in activities)
    total_study_time = sum(a.study_time_minutes for a in activities)
    goals_met_count = sum(1 for a in activities if a.daily_goal_met)

    # Fetch streak for current_streak / longest_streak
    streak_result = await db.execute(select(Streak).where(Streak.user_id == current_user.id))
    streak = streak_result.scalar_one_or_none()

    # Create a map for quick lookup
    activity_map = {a.activity_date: a for a in activities}

    # Build response for each day of the week
    days = []
    day_names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

    total_xp = 0
    best_day = None
    best_xp = 0
    
    for i in range(7):
        day_date = week_start + timedelta(days=i)
        activity = activity_map.get(day_date)
        
        xp = activity.xp_earned if activity else 0
        lessons = activity.lessons_completed if activity else 0
        minutes = activity.study_time_minutes if activity else 0
        goal_met = activity.daily_goal_met if activity else False
        
        total_xp += xp
        if xp > best_xp:
            best_xp = xp
            best_day = day_names[day_date.weekday()]
        
        days.append({
            'date': day_date.isoformat(),
            'day_name': day_names[day_date.weekday()],
            'xp_earned': xp,
            'lessons_completed': lessons,
            'study_time_minutes': minutes,
            'daily_goal_met': goal_met,
            'is_today': day_date == today,
        })
    
    # Calculate stats
    days_with_activity = len([d for d in days if d['xp_earned'] > 0])
    average_xp = round(total_xp / 7, 1) if total_xp > 0 else 0
    
    response_data = {
        'days': days,
        'total_xp': total_xp,
        'average_xp': average_xp,
        'best_day': best_day,
        'days_active': days_with_activity,
        'week_start': week_start.isoformat(),
        'week_end': today.isoformat(),
        'total_lessons': total_lessons,
        'total_study_time': total_study_time,
        'week_goal_progress': round(goals_met_count / 7, 2),
        'current_streak': streak.current_streak if streak else 0,
        'longest_streak': streak.longest_streak if streak else 0,
    }
    
    return ApiResponse(
        success=True,
        message="Weekly progress retrieved successfully",
        data=response_data
    )


# ============================================================================
# Streak Endpoints
# ============================================================================

@router.get("/streak", response_model=ApiResponse[dict])
async def get_my_streak(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's streak information
    
    Returns:
    - current_streak: Current consecutive days
    - longest_streak: Best streak ever achieved
    - total_days_active: Total days with learning activity
    - last_activity_date: Last date of learning activity
    - freeze_count: Available streak freezes
    - is_active_today: Whether user has learned today
    - streak_at_risk: Whether streak will be lost if no activity today
    """
    uid = str(current_user.id)
    cache_key = build_cache_key("progress_streak", user_id=uid)
    cached = await get_cached(cache_key)
    if cached is not None:
        if all(k in cached for k in ['previous_streak', 'restores_used_this_month', 'restores_remaining', 'can_restore', 'is_daily_reward_available']):
            return ApiResponse(success=True, message="Streak retrieved successfully", data=cached)

    result = await db.execute(
        select(Streak).where(Streak.user_id == current_user.id)
    )
    streak = result.scalar_one_or_none()
    
    today = date.today()
    
    if not streak:
        # Create new streak record for user — handle race condition
        try:
            streak = Streak(
                user_id=current_user.id,
                current_streak=0,
                longest_streak=0,
                total_days_active=0,
                freeze_count=0,
                previous_streak=0,
                restores_used_this_month=0
            )
            db.add(streak)
            await db.commit()
            await db.refresh(streak)
        except Exception:
            await db.rollback()
            # Another concurrent request created it — re-fetch
            result = await db.execute(
                select(Streak).where(Streak.user_id == current_user.id)
            )
            streak = result.scalar_one_or_none()
            if not streak:
                raise
    else:
        # Check monthly reset for restores
        if streak.last_restore_date and (today.year != streak.last_restore_date.year or today.month != streak.last_restore_date.month):
            streak.restores_used_this_month = 0
            await db.commit()
            await db.refresh(streak)
    
    # Determine if active today and if streak is at risk
    is_active_today = streak.last_activity_date == today if streak.last_activity_date else False
    
    # Streak is at risk if last activity was yesterday and no activity today
    streak_at_risk = False
    if streak.last_activity_date and not is_active_today:
        yesterday = today - timedelta(days=1)
        streak_at_risk = streak.last_activity_date == yesterday

    # Build weekly_activity: 7 booleans Mon–Sun for the current ISO week
    # today.weekday(): 0=Mon, 6=Sun
    monday = today - timedelta(days=today.weekday())
    sunday = monday + timedelta(days=6)
    weekly_activity = [False] * 7

    # Query DailyActivity records for this week
    daily_result = await db.execute(
        select(DailyActivity.activity_date).where(
            and_(
                DailyActivity.user_id == current_user.id,
                DailyActivity.activity_date >= monday,
                DailyActivity.activity_date <= sunday,
            )
        )
    )
    active_dates = {row[0] for row in daily_result.fetchall()}

    # Also count today as active if is_active_today (based on streak record)
    if is_active_today:
        active_dates.add(today)

    for i in range(7):
        day = monday + timedelta(days=i)
        weekly_activity[i] = day in active_dates

    response_data = {
        'current_streak': streak.current_streak,
        'longest_streak': streak.longest_streak,
        'total_days_active': streak.total_days_active,
        'last_activity_date': streak.last_activity_date.isoformat() if streak.last_activity_date else None,
        'freeze_count': streak.freeze_count,
        'is_active_today': is_active_today,
        'streak_at_risk': streak_at_risk and streak.current_streak > 0,
        'weekly_activity': weekly_activity,
        'previous_streak': streak.previous_streak if isinstance(streak.previous_streak, int) else 0,
        'restores_used_this_month': streak.restores_used_this_month if isinstance(streak.restores_used_this_month, int) else 0,
        'restores_remaining': max(0, 3 - (streak.restores_used_this_month if isinstance(streak.restores_used_this_month, int) else 0)),
        'can_restore': (streak.previous_streak if isinstance(streak.previous_streak, int) else 0) > 0 and (streak.restores_used_this_month if isinstance(streak.restores_used_this_month, int) else 0) < 3,
        'is_daily_reward_available': is_active_today and (streak.last_reward_claim_date != today or streak.last_reward_claim_date is None),
    }

    await set_cached(cache_key, response_data, ttl=30)

    return ApiResponse(
        success=True,
        message="Streak retrieved successfully",
        data=response_data
    )


@router.post("/streak/update", response_model=ApiResponse[dict])
async def update_streak(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Update user's streak after learning activity
    
    Called when user completes a lesson or review session.
    Automatically handles:
    - Creating streak if first time
    - Incrementing streak for consecutive days
    - Resetting streak if gap > 1 day
    - Using streak freeze if available
    - Updating longest streak
    
    Returns:
    - Updated streak information
    - streak_increased: Whether streak went up
    - streak_saved: Whether freeze was used
    """
    streak, streak_increased, streak_saved, unlocked_achievements = await update_user_streak(db, current_user.id)
    await db.commit()
    await db.refresh(streak)
    
    message = "Streak updated"
    if streak_saved:
        message = "Streak freeze used! Your streak is saved"
    elif streak_increased:
        message = f"{streak.current_streak} day streak!"
    
    response_data = {
        'current_streak': streak.current_streak,
        'longest_streak': streak.longest_streak,
        'total_days_active': streak.total_days_active,
        'freeze_count': streak.freeze_count,
        'streak_increased': streak_increased,
        'streak_saved': streak_saved,
        'achievements_unlocked': unlocked_achievements,
        'previous_streak': streak.previous_streak if isinstance(streak.previous_streak, int) else 0,
        'restores_used_this_month': streak.restores_used_this_month if isinstance(streak.restores_used_this_month, int) else 0,
        'restores_remaining': max(0, 3 - (streak.restores_used_this_month if isinstance(streak.restores_used_this_month, int) else 0)),
        'can_restore': (streak.previous_streak if isinstance(streak.previous_streak, int) else 0) > 0 and (streak.restores_used_this_month if isinstance(streak.restores_used_this_month, int) else 0) < 3,
        'is_daily_reward_available': streak.last_activity_date == date.today() and (streak.last_reward_claim_date != date.today() or streak.last_reward_claim_date is None),
    }

    return ApiResponse(
        success=True,
        message=message,
        data=response_data
    )


@router.post("/streak/freeze", response_model=ApiResponse[dict])
async def use_streak_freeze(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Use a streak freeze to protect current streak
    
    Streak freezes prevent streak loss when missing a day.
    Can only be used if:
    - User has streak freezes available
    - Streak is at risk (no activity today, had activity yesterday)
    
    Returns:
    - Success/failure status
    - Remaining freeze count
    """
    result = await db.execute(
        select(Streak).where(Streak.user_id == current_user.id)
    )
    streak = result.scalar_one_or_none()
    
    if not streak:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No streak record found"
        )
    
    if streak.freeze_count <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No streak freezes available. Purchase from shop."
        )
    
    today = date.today()
    
    # Check if freeze is needed
    if streak.last_activity_date == today:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Streak is already active today, no freeze needed"
        )
    
    # Use the freeze
    streak.freeze_count -= 1
    streak.last_activity_date = today  # Mark as "covered" for today
    
    await db.commit()
    await db.refresh(streak)
    
    return ApiResponse(
        success=True,
        message=f"Streak freeze activated! {streak.freeze_count} freezes remaining",
        data={
            'current_streak': streak.current_streak,
            'freeze_count': streak.freeze_count,
            'freeze_used': True
        }
    )


@router.post("/streak/restore", response_model=ApiResponse[dict])
async def restore_streak(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Restore a broken streak using one of the 3 monthly restores
    """
    result = await db.execute(
        select(Streak).where(Streak.user_id == current_user.id)
    )
    streak = result.scalar_one_or_none()
    
    if not streak:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No streak record found to restore"
        )
        
    today = date.today()
    
    # Check monthly reset
    if streak.last_restore_date and (today.year != streak.last_restore_date.year or today.month != streak.last_restore_date.month):
        streak.restores_used_this_month = 0
        
    if streak.restores_used_this_month >= 3:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already used your 3 streak restores for this month"
        )
        
    if streak.previous_streak <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No previous streak is available to restore"
        )
        
    # Restore the streak: current_streak = previous_streak + 1
    old_streak = streak.previous_streak
    streak.current_streak = old_streak + 1
    streak.previous_streak = 0
    streak.last_restore_date = today
    streak.restores_used_this_month += 1
    
    if streak.current_streak > streak.longest_streak:
        streak.longest_streak = streak.current_streak
        
    await db.commit()
    await db.refresh(streak)
    
    # Invalidate cache
    uid = str(current_user.id)
    await delete_cached(build_cache_key("progress_streak", user_id=uid))
    await delete_cached(build_cache_key("progress_me", user_id=uid))
    
    response_data = {
        'current_streak': streak.current_streak,
        'longest_streak': streak.longest_streak,
        'total_days_active': streak.total_days_active,
        'freeze_count': streak.freeze_count,
        'previous_streak': streak.previous_streak,
        'restores_used_this_month': streak.restores_used_this_month,
        'restores_remaining': max(0, 3 - streak.restores_used_this_month),
        'can_restore': False,
        'is_daily_reward_available': streak.last_activity_date == today and (streak.last_reward_claim_date != today or streak.last_reward_claim_date is None),
    }
    
    return ApiResponse(
        success=True,
        message=f"Streak restored to {streak.current_streak} days!",
        data=response_data
    )


@router.post("/streak/claim-daily-reward", response_model=ApiResponse[dict])
async def claim_daily_reward(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Claim the daily login reward based on current streak cycle (1-7 days)
    """
    result = await db.execute(
        select(Streak).where(Streak.user_id == current_user.id)
    )
    streak = result.scalar_one_or_none()
    
    if not streak:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No streak record found"
        )
        
    today = date.today()
    
    if streak.last_activity_date != today:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You must complete a learning activity today before claiming your reward"
        )
        
    if streak.last_reward_claim_date == today:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already claimed today's reward"
        )
        
    # Calculate gems based on streak cycle:
    # 7-day cycle: 5, 10, 15, 20, 25, 30, 50 gems
    rewards_cycle = [5, 10, 15, 20, 25, 30, 50]
    day_index = (streak.current_streak - 1) % 7
    reward_gems = rewards_cycle[day_index]
    
    # Award gems
    wallet, transaction = await WalletCRUD.add_gems(
        db=db,
        user_id=current_user.id,
        amount=reward_gems,
        source="daily_streak_reward",
        description=f"Claimed {reward_gems} gems for day {day_index + 1} of streak",
        commit=False
    )
    
    streak.last_reward_claim_date = today
    await db.commit()
    await db.refresh(streak)
    
    # Invalidate cache
    uid = str(current_user.id)
    await delete_cached(build_cache_key("progress_streak", user_id=uid))
    await delete_cached(build_cache_key("progress_me", user_id=uid))
    
    response_data = {
        'gems_awarded': reward_gems,
        'total_gems': wallet.gems,
        'current_streak': streak.current_streak,
        'is_daily_reward_available': False,
    }
    
    return ApiResponse(
        success=True,
        message=f"Successfully claimed {reward_gems} gems!",
        data=response_data
    )
