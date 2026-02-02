"""
User Routes
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from datetime import datetime, timedelta

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.progress import UserProgress, LessonAttempt, Streak
from app.models.gamification import UserAchievement, UserWallet
from app.models.vocabulary import UserVocabulary
from app.schemas.user import UserResponse, UserUpdate
from app.schemas.common import MessageResponse, ApiResponse
from app.schemas.level import (
    LevelInfoResponse,
    UserStatsResponse,
    WeeklyActivityResponse,
    WeeklyActivityData,
    XPAwardRequest,
    XPAwardResponse
)
from app.services.level_service import LevelService

router = APIRouter()


@router.get("/me", response_model=UserResponse)
async def get_current_user_profile(
    current_user: User = Depends(get_current_user)
):
    """
    Get current user profile.
    
    Requires authentication.
    """
    return current_user


@router.put("/me", response_model=UserResponse)
async def update_current_user_profile(
    update_data: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update current user profile.
    
    Only non-null fields will be updated.
    """
    # Update user fields
    update_dict = update_data.model_dump(exclude_unset=True)
    
    for field, value in update_dict.items():
        setattr(current_user, field, value)
    
    await db.commit()
    await db.refresh(current_user)
    
    return current_user


@router.delete("/me", response_model=MessageResponse)
async def delete_current_user(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Delete current user account.
    
    This is a soft delete (sets is_active to False).
    """
    current_user.is_active = False
    await db.commit()
    
    return MessageResponse(
        message="Account deactivated successfully",
        detail="Your account has been deactivated. Contact support to reactivate."
    )


@router.get("/{user_id}", response_model=UserResponse)
async def get_user_by_id(
    user_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)  # Require auth
):
    """
    Get user by ID.
    
    Returns public user information.
    """
    from sqlalchemy import select
    
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    return user


# =====================
# Level & Stats Endpoints
# =====================

@router.get("/me/level", response_model=ApiResponse[LevelInfoResponse])
async def get_user_level(
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's level information.
    
    Returns:
    - All level tiers
    - Current level status with XP progress
    """
    level_status = LevelService.calculate_level_status(current_user.total_xp)
    all_tiers = LevelService.get_all_tiers()
    
    return ApiResponse(
        success=True,
        data=LevelInfoResponse(
            all_tiers=all_tiers,
            current_level=level_status
        ),
        message="Level information retrieved successfully"
    )


@router.get("/me/stats", response_model=ApiResponse[UserStatsResponse])
async def get_user_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get comprehensive user statistics.
    
    Includes:
    - Level and XP
    - Course progress
    - Learning stats
    - Streak information
    - Vocabulary stats
    - Achievements
    """
    # Calculate level status
    level_status = LevelService.calculate_level_status(current_user.total_xp)
    
    # Get course stats
    courses_query = select(func.count(UserProgress.id)).where(
        UserProgress.user_id == current_user.id
    )
    courses_enrolled = (await db.execute(courses_query)).scalar() or 0
    
    completed_query = select(func.count(UserProgress.id)).where(
        UserProgress.user_id == current_user.id,
        UserProgress.status == "completed"
    )
    courses_completed = (await db.execute(completed_query)).scalar() or 0
    
    # Get lesson stats
    lessons_query = select(func.count(LessonAttempt.id)).where(
        LessonAttempt.user_id == current_user.id,
        LessonAttempt.passed == True
    )
    lessons_completed = (await db.execute(lessons_query)).scalar() or 0
    
    # Get study time (sum of all lesson attempts in ms, convert to minutes)
    study_time_query = select(func.sum(LessonAttempt.time_spent_ms)).where(
        LessonAttempt.user_id == current_user.id
    )
    total_study_time = (await db.execute(study_time_query)).scalar() or 0
    total_study_time = int(total_study_time / 60000) if total_study_time else 0  # ms to minutes
    
    # Get streak info
    streak_query = select(Streak).where(Streak.user_id == current_user.id)
    streak_result = await db.execute(streak_query)
    streak = streak_result.scalar_one_or_none()
    
    current_streak = streak.current_streak if streak else 0
    longest_streak = streak.longest_streak if streak else 0
    
    # Get vocabulary stats
    vocab_learned_query = select(func.count(UserVocabulary.id)).where(
        UserVocabulary.user_id == current_user.id
    )
    words_learned = (await db.execute(vocab_learned_query)).scalar() or 0
    
    vocab_mastered_query = select(func.count(UserVocabulary.id)).where(
        UserVocabulary.user_id == current_user.id,
        UserVocabulary.mastery_level >= 4  # Assuming 4+ is "mastered"
    )
    words_mastered = (await db.execute(vocab_mastered_query)).scalar() or 0
    
    # Get achievements count
    achievements_query = select(func.count(UserAchievement.id)).where(
        UserAchievement.user_id == current_user.id
    )
    achievements_unlocked = (await db.execute(achievements_query)).scalar() or 0
    
    # Get gems
    wallet_query = select(UserWallet).where(UserWallet.user_id == current_user.id)
    wallet_result = await db.execute(wallet_query)
    wallet = wallet_result.scalar_one_or_none()
    total_gems = wallet.gems_balance if wallet else 0
    
    return ApiResponse(
        success=True,
        data=UserStatsResponse(
            total_xp=current_user.total_xp,
            level=level_status,
            courses_enrolled=courses_enrolled,
            courses_completed=courses_completed,
            lessons_completed=lessons_completed,
            total_study_time=total_study_time,
            current_streak=current_streak,
            longest_streak=longest_streak,
            words_learned=words_learned,
            words_mastered=words_mastered,
            achievements_unlocked=achievements_unlocked,
            total_gems=total_gems
        ),
        message="User stats retrieved successfully"
    )


@router.get("/me/weekly-activity", response_model=ApiResponse[WeeklyActivityResponse])
async def get_weekly_activity(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get user's activity for the past 7 days.
    
    Returns:
    - Daily XP earned
    - Lessons completed
    - Study time
    """
    # Calculate date range (last 7 days)
    today = datetime.utcnow().date()
    week_ago = today - timedelta(days=6)
    
    # Initialize data for each day
    days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    week_data = []
    total_xp = 0
    total_lessons = 0
    total_study_time = 0
    
    for i in range(7):
        day_date = week_ago + timedelta(days=i)
        day_start = datetime.combine(day_date, datetime.min.time())
        day_end = datetime.combine(day_date, datetime.max.time())
        
        # Get lessons completed on this day
        lessons_query = select(
            func.count(LessonAttempt.id).label('count'),
            func.coalesce(func.sum(LessonAttempt.xp_earned), 0).label('xp'),
            func.coalesce(func.sum(LessonAttempt.time_spent_ms), 0).label('time')
        ).where(
            LessonAttempt.user_id == current_user.id,
            LessonAttempt.finished_at >= day_start,
            LessonAttempt.finished_at <= day_end,
            LessonAttempt.passed == True
        )
        
        result = await db.execute(lessons_query)
        row = result.first()
        
        lessons_count = int(row.count) if row and row.count else 0
        xp = int(row.xp) if row and row.xp else 0
        time = int(row.time / 60000) if row and row.time else 0  # Convert ms to minutes
        
        # Get day of week name
        day_name = days[day_date.weekday()]
        
        week_data.append(WeeklyActivityData(
            day=day_name,
            xp=xp,
            lessons=lessons_count,
            study_time=time
        ))
        
        total_xp += xp
        total_lessons += lessons_count
        total_study_time += time
    
    return ApiResponse(
        success=True,
        data=WeeklyActivityResponse(
            week_data=week_data,
            total_xp=total_xp,
            total_lessons=total_lessons,
            total_study_time=total_study_time
        ),
        message="Weekly activity retrieved successfully"
    )


@router.post("/me/xp", response_model=ApiResponse[XPAwardResponse])
async def award_xp(
    xp_data: XPAwardRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Award XP to the current user.
    
    This endpoint is typically called by other services after completing actions.
    Returns level up information if user leveled up.
    """
    old_xp = current_user.total_xp
    new_xp = old_xp + xp_data.amount
    
    # Check if user leveled up
    leveled_up, previous_tier = LevelService.check_level_up(old_xp, new_xp)
    
    # Update user XP and level
    current_user.total_xp = new_xp
    if leveled_up:
        new_level_status = LevelService.calculate_level_status(new_xp)
        current_user.level = new_level_status.current_tier.code
    
    await db.commit()
    await db.refresh(current_user)
    
    # Calculate new level status
    level_status = LevelService.calculate_level_status(new_xp)
    
    return ApiResponse(
        success=True,
        data=XPAwardResponse(
            total_xp=new_xp,
            xp_gained=xp_data.amount,
            new_level=level_status,
            level_up=leveled_up,
            previous_tier=previous_tier
        ),
        message=f"Awarded {xp_data.amount} XP" + (" - Level Up!" if leveled_up else "")
    )
