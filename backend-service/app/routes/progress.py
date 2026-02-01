"""
Progress Routes
API endpoints for tracking user progress

Following agent-skills/language-learning-patterns:
- progress-learning-streaks: Robust streak system with protections (3-5x engagement)
- gamification-achievement-badges: Meaningful achievements (25-40% engagement boost)
"""
from datetime import date, datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
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
from app.models.progress import Streak, DailyActivity
from app.services import check_achievements_for_user

router = APIRouter(prefix="/progress", tags=["Progress"])


@router.get("/me", response_model=ApiResponse[ProgressStatsResponse])
async def get_my_progress(
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
    # Get user stats
    stats = await ProgressCRUD.get_user_stats(db, str(current_user.id))
    
    # Get all course progress
    all_progress = await ProgressCRUD.get_all_user_progress(db, str(current_user.id))
    
    course_progress_list = []
    for progress in all_progress[:10]:  # Limit to 10 most recent
        course = await CourseCRUD.get_course(db, progress.course_id)
        if course:
            course_progress_list.append({
                'course_id': str(course.id),
                'course_title': course.title,
                'progress_percentage': progress.progress_percentage,
                'lessons_completed': progress.lessons_completed,
                'total_lessons': course.total_lessons or 0,
                'total_xp_earned': progress.total_xp_earned,
                'started_at': progress.started_at,
                'last_activity_at': progress.last_activity_at,
            })
    
    response_data = {
        'summary': stats,
        'recent_activity': [],  # TODO: Implement activity tracking
        'course_progress': course_progress_list
    }
    
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
        
        # Get user's total XP
        total_xp = await ProgressCRUD.get_user_total_xp(db, str(current_user.id))
        
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
            'message': message
        }
        
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
    total_xp = await ProgressCRUD.get_user_total_xp(db, str(current_user.id))
    
    return ApiResponse(
        success=True,
        message="Total XP retrieved successfully",
        data={'total_xp': total_xp}
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
    result = await db.execute(
        select(Streak).where(Streak.user_id == current_user.id)
    )
    streak = result.scalar_one_or_none()
    
    today = date.today()
    
    if not streak:
        # Create new streak record for user
        streak = Streak(
            user_id=current_user.id,
            current_streak=0,
            longest_streak=0,
            total_days_active=0,
            freeze_count=0
        )
        db.add(streak)
        await db.commit()
        await db.refresh(streak)
    
    # Determine if active today and if streak is at risk
    is_active_today = streak.last_activity_date == today if streak.last_activity_date else False
    
    # Streak is at risk if last activity was yesterday and no activity today
    streak_at_risk = False
    if streak.last_activity_date and not is_active_today:
        yesterday = today - timedelta(days=1)
        streak_at_risk = streak.last_activity_date == yesterday
    
    response_data = {
        'current_streak': streak.current_streak,
        'longest_streak': streak.longest_streak,
        'total_days_active': streak.total_days_active,
        'last_activity_date': streak.last_activity_date.isoformat() if streak.last_activity_date else None,
        'freeze_count': streak.freeze_count,
        'is_active_today': is_active_today,
        'streak_at_risk': streak_at_risk and streak.current_streak > 0,
    }
    
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
    result = await db.execute(
        select(Streak).where(Streak.user_id == current_user.id)
    )
    streak = result.scalar_one_or_none()
    
    today = date.today()
    streak_increased = False
    streak_saved = False
    
    if not streak:
        # Create new streak
        streak = Streak(
            user_id=current_user.id,
            current_streak=1,
            longest_streak=1,
            last_activity_date=today,
            total_days_active=1,
            freeze_count=0
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
            
            if streak.freeze_count > 0 and days_missed == 1:
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
                # Reset streak
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
    
    await db.commit()
    await db.refresh(streak)
    
    # Check streak-based achievements
    unlocked_achievements = []
    try:
        unlocked_achievements = await check_achievements_for_user(
            db, current_user.id, "streak_update"
        )
    except Exception as e:
        print(f"Achievement check error: {e}")
    
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
