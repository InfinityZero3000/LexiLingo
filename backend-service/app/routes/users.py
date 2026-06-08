"""
User Routes
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.progress import UserProgress, LessonAttempt, Streak, UserCourseProgress, LessonCompletion
from app.models.gamification import UserAchievement, UserWallet
from app.models.vocabulary import UserVocabulary
from app.schemas.user import UserResponse, UserUpdate
from app.schemas.common import MessageResponse, ApiResponse
from app.schemas.level import (
    LevelInfoResponse,
    LevelFullResponse,
    UserStatsResponse,
    WeeklyActivityResponse,
    WeeklyActivityData,
    XPAwardRequest,
    XPAwardResponse
)
from app.services.level_service import LevelService, get_numeric_level_progress, calculate_numeric_level
from app.services.rank_service import (
    apply_rank_info_to_user,
    calculate_rank as calc_rank,
)

router = APIRouter()


def _safe_str(value, default: str) -> str:
    if value is None:
        return default
    text = str(value).strip()
    return text if text else default


def _safe_int(value, default: int) -> int:
    try:
        if value is None:
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def _serialize_user_response(user: User) -> UserResponse:
    normalized_level = _safe_str(getattr(user, "level", None), "A1").upper()
    role_slug = _safe_str(getattr(user, "role_slug", None), "user")
    role_level = _safe_int(getattr(user, "role_level", None), 0)

    return UserResponse(
        id=user.id,
        email=user.email,
        username=user.username,
        display_name=getattr(user, "display_name", None),
        native_language=_safe_str(getattr(user, "native_language", None), "vi"),
        target_language=_safe_str(getattr(user, "target_language", None), "en"),
        level=normalized_level,
        avatar_url=getattr(user, "avatar_url", None),
        is_active=bool(getattr(user, "is_active", True)),
        is_verified=bool(getattr(user, "is_verified", False)),
        is_onboarding_completed=bool(
            getattr(user, "is_onboarding_completed", False),
        ),
        created_at=getattr(user, "created_at"),
        last_login=getattr(user, "last_login", None),
        cefr_level=_safe_str(getattr(user, "cefr_level", None), normalized_level),
        total_xp=_safe_int(getattr(user, "total_xp", None), 0),
        numeric_level=_safe_int(getattr(user, "numeric_level", None), 1),
        rank=_safe_str(getattr(user, "rank", None), "bronze"),
        rank_score=float(getattr(user, "rank_score", 0) or 0),
        rank_level_score=float(getattr(user, "rank_level_score", 0) or 0),
        rank_proficiency_score=float(
            getattr(user, "rank_proficiency_score", 0) or 0,
        ),
        role_id=getattr(user, "role_id", None),
        role_slug=role_slug,
        role_level=role_level,
        is_admin=role_level >= 50,
        is_super_admin=role_level >= 100,
    )


@router.get("/me", response_model=UserResponse)
async def get_current_user_profile(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get current user profile.
    
    Requires authentication.
    """
    # Always recalculate rank on profile fetch to ensure UI is up-to-date
    # with the latest gamification constants
    rank_info = calc_rank(
        numeric_level=current_user.numeric_level or 1,
        proficiency_level=current_user.level or "A1"
    )
    apply_rank_info_to_user(current_user, rank_info)
    await db.commit()
    
    return _serialize_user_response(current_user)


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
        
    rank_info = calc_rank(
        numeric_level=current_user.numeric_level or 1,
        proficiency_level=current_user.level or "A1"
    )
    apply_rank_info_to_user(current_user, rank_info)
    
    await db.commit()
    await db.refresh(current_user)
    
    return _serialize_user_response(current_user)


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


@router.get("/search", response_model=List[dict])
async def search_users(
    q: str = Query(..., min_length=1, max_length=100, description="Search query"),
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Search users by username or display_name.
    Returns a list of social profile objects for the Social feature.
    """
    from app.models.gamification import UserFollowing
    from sqlalchemy import and_

    pattern = f"%{q}%"
    result = await db.execute(
        select(User)
        .where(
            and_(
                User.is_active == True,
                User.id != current_user.id,
                or_(
                    User.username.ilike(pattern),
                    User.display_name.ilike(pattern),
                ),
            )
        )
        .limit(limit)
    )
    users = result.scalars().all()

    # Batch-check which ones the current user is already following
    if users:
        user_ids = [u.id for u in users]
        following_result = await db.execute(
            select(UserFollowing.following_id).where(
                and_(
                    UserFollowing.follower_id == current_user.id,
                    UserFollowing.following_id.in_(user_ids),
                )
            )
        )
        following_set = {row[0] for row in following_result.all()}
    else:
        following_set = set()

    return [
        {
            "user_id": str(u.id),
            "username": u.username or "",
            "display_name": u.display_name or u.username or "",
            "avatar_url": u.avatar_url,
            "total_xp": u.total_xp or 0,
            "current_streak": 0,
            "league": "bronze",
            "is_following": u.id in following_set,
            "mutual_connections": 0,
            "suggestion_reasons": [],
        }
        for u in users
    ]


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
    
    return _serialize_user_response(user)


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


@router.get("/me/level-full", response_model=ApiResponse[LevelFullResponse])
async def get_user_level_full(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Get full level info including numeric level, rank, and proficiency.
    
    Returns:
    - Numeric level with XP progress to next level
    - CEFR proficiency level
    - Rank tier with weighted score
    """
    # Numeric level info
    level_info = get_numeric_level_progress(current_user.total_xp)
    
    # CEFR proficiency (authoritative from persisted profile)
    normalized_cefr = (current_user.level or "A1").upper()
    persisted_tier = LevelService.get_tier_by_code(normalized_cefr)
    if persisted_tier is None:
        persisted_tier = LevelService.get_tier_by_code("A1")

    # XP-derived CEFR kept as diagnostic signal only (not profile source-of-truth)
    xp_derived_status = LevelService.calculate_level_status(current_user.total_xp)
    
    # Rank info
    rank_info = calc_rank(
        numeric_level=level_info.numeric_level,
        proficiency_level=current_user.level
    )
    apply_rank_info_to_user(current_user, rank_info)
    await db.commit()
    
    return ApiResponse(
        success=True,
        data=LevelFullResponse(
            numeric_level=level_info.numeric_level,
            current_xp_in_level=level_info.current_xp_in_level,
            xp_for_next_level=level_info.xp_for_next_level,
            level_progress_percent=level_info.level_progress_percent,
            total_xp=current_user.total_xp,
            cefr_level=persisted_tier.code,
            cefr_name=persisted_tier.name,
            cefr_progression_source="profile",
            xp_derived_cefr_level=xp_derived_status.current_tier.code,
            xp_derived_cefr_name=xp_derived_status.current_tier.name,
            # Backward-compatible fields for existing clients.
            proficiency_level=persisted_tier.code,
            proficiency_name=persisted_tier.name,
            rank=rank_info.rank.value,
            rank_name=rank_info.name,
            rank_score=round(rank_info.score, 2),
            rank_color=rank_info.color,
            rank_icon=rank_info.icon,
            rank_icon_url=rank_info.icon_url,
        ),
        message="Full level information retrieved successfully"
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
    
    # Get course stats from user_course_progress (active progress system)
    courses_query = select(func.count(UserCourseProgress.id)).where(
        UserCourseProgress.user_id == current_user.id
    )
    courses_enrolled = (await db.execute(courses_query)).scalar() or 0

    completed_query = select(func.count(UserCourseProgress.id)).where(
        UserCourseProgress.user_id == current_user.id,
        UserCourseProgress.progress_percentage >= 100
    )
    courses_completed = (await db.execute(completed_query)).scalar() or 0

    # Get lesson stats from lesson_completions (active progress system)
    lessons_query = select(func.count(LessonCompletion.id)).where(
        LessonCompletion.user_id == current_user.id,
        LessonCompletion.is_passed == True
    )
    lessons_completed = (await db.execute(lessons_query)).scalar() or 0

    # Get study time from lesson_attempts (still used for session metadata)
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
        UserVocabulary.status == 'mastered'  # Use status field instead of mastery_level
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
    total_gems = wallet.gems if wallet else 0
    
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
    today = datetime.now(timezone.utc).date()
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
    
    Automatically applies active XP boosts (double_xp) if any.
    """
    from app.services.item_effects_service import ItemEffectsService
    
    # Check for active XP boosts
    effects_service = ItemEffectsService(db)
    multiplier = await effects_service.get_xp_multiplier(current_user.id)
    
    # Apply multiplier to XP amount
    base_amount = xp_data.amount
    boosted_amount = int(base_amount * multiplier)
    
    old_xp = current_user.total_xp
    new_xp = old_xp + boosted_amount
    
    # Check if user leveled up
    leveled_up, previous_tier = LevelService.check_level_up(old_xp, new_xp)
    
    # Update user XP, level, numeric_level, and rank
    current_user.total_xp = new_xp
    if leveled_up:
        new_level_status = LevelService.calculate_level_status(new_xp)
        current_user.level = new_level_status.current_tier.code
    
    current_user.numeric_level = calculate_numeric_level(new_xp)
    
    # Recalculate rank
    rank_info = calc_rank(current_user.numeric_level, current_user.level or "A1")
    apply_rank_info_to_user(current_user, rank_info)
    
    await db.commit()
    await db.refresh(current_user)
    
    # Calculate new level status
    level_status = LevelService.calculate_level_status(new_xp)
    
    # Build message including boost info
    message = f"Awarded {boosted_amount} XP"
    if multiplier > 1.0:
        message = f"Awarded {boosted_amount} XP ({base_amount} × {multiplier}x boost)"
    if leveled_up:
        message += " - Level Up!"
    
    return ApiResponse(
        success=True,
        data=XPAwardResponse(
            total_xp=new_xp,
            xp_gained=boosted_amount,
            new_level=level_status,
            level_up=leveled_up,
            previous_tier=previous_tier
        ),
        message=message
    )
