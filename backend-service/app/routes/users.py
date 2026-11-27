"""
User Routes
"""

import uuid as uuid_lib
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from datetime import UTC, datetime

from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.core.token_blacklist import InactiveUserFlag
from app.core.firebase_auth import revoke_all_refresh_tokens
from app.services.role_guard import ensure_not_last_super_admin, ensure_recent_sign_in
from app.crud.user import UserCRUD
from app.models.user import User
from app.services.cefr_level_service import (
    apply_level_change,
    get_or_create_profile,
    level_verified,
    normalise_level,
    publish_level_change,
)
from app.schemas.user import UserResponse, UserUpdate, lexi_reply_language_of
from app.schemas.start_learning import StartLearningRequest, StartLearningResponse
from app.crud.course import CourseCRUD
from app.services.start_learning_service import find_start_target
from app.services.learner_state import bump_learner_state_epoch
from app.services.lessons_completed import count_completed_lessons
from app.schemas.common import MessageResponse, ApiResponse
from app.schemas.level import (
    LevelFullResponse,
    UserStatsResponse,
    WeeklyActivityResponse,
)
from app.services.level_service import LevelService, get_numeric_level_progress
from app.services.rank_service import apply_rank_info_to_user, calculate_rank as calc_rank, rank_proficiency_level
from app.services.user_stats_service import (
    get_user_stats,
    get_weekly_activity,
)
from app.services.user_deletion_service import permanently_delete_user

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


def _serialize_user_response(user: User, lessons_completed: int = 0) -> UserResponse:
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
        lexi_reply_language=lexi_reply_language_of(
            getattr(user, "lexi_reply_language", None)
        ),
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
        certified_level=rank_proficiency_level(user),
        level_verified=level_verified(user),
        goal=getattr(user, "goal", None),
        interest=getattr(user, "interest", None),
        total_xp=_safe_int(getattr(user, "total_xp", None), 0),
        lessons_completed=lessons_completed,
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
        is_admin=role_level >= 1,
        is_super_admin=role_level >= 2,
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
        proficiency_level=rank_proficiency_level(current_user)
    )
    apply_rank_info_to_user(current_user, rank_info)
    await db.commit()
    
    return _serialize_user_response(
        current_user, await count_completed_lessons(db, current_user.id)
    )


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

    # The level is the learner's working level; it goes through the one writer
    # so the history row, the rank and the learner-state epoch all follow. It
    # never moves the certified level, so it cannot buy rank.
    reported_level = normalise_level(
        update_dict.pop("level", None) or update_dict.pop("cefr_level", None)
    )
    update_dict.pop("cefr_level", None)
    level_change = None
    if reported_level is not None:
        profile = await get_or_create_profile(db, current_user)
        level_change = await apply_level_change(
            db, current_user, profile, source="self", working=reported_level
        )

    for field, value in update_dict.items():
        setattr(current_user, field, value)

    if "goal" in update_dict or "interest" in update_dict:
        await bump_learner_state_epoch(db, current_user.id, datetime.now(UTC))

    rank_info = calc_rank(
        numeric_level=current_user.numeric_level or 1,
        proficiency_level=rank_proficiency_level(current_user)
    )
    apply_rank_info_to_user(current_user, rank_info)
    
    await db.commit()
    await db.refresh(current_user)
    await publish_level_change(level_change)

    return _serialize_user_response(
        current_user, await count_completed_lessons(db, current_user.id)
    )


_AVATAR_MEDIA_DIR = Path("/app/data/media")
_MAX_AVATAR_BYTES = 2 * 1024 * 1024


def _avatar_extension(head: bytes) -> str | None:
    """Sniff the real format; the client-declared content type and filename are not trusted."""
    if head.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return ".webp"
    return None


@router.post("/me/avatar", response_model=UserResponse)
async def upload_current_user_avatar(
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Store an uploaded JPEG/PNG/WebP (max 2 MB) as the caller's avatar."""
    contents = await file.read(_MAX_AVATAR_BYTES + 1)
    if len(contents) > _MAX_AVATAR_BYTES:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "Avatar too large. Maximum 2MB allowed.")
    extension = _avatar_extension(contents[:12])
    if extension is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Avatar must be a JPEG, PNG or WebP image.")

    target_dir = _AVATAR_MEDIA_DIR / "avatars"
    target_dir.mkdir(parents=True, exist_ok=True)
    name = f"{current_user.id}-{uuid_lib.uuid4().hex[:12]}{extension}"
    (target_dir / name).write_bytes(contents)
    for old in target_dir.glob(f"{current_user.id}-*"):
        if old.name != name:
            old.unlink(missing_ok=True)

    origin = settings.MEDIA_PUBLIC_BASE_URL.rstrip("/") or str(request.base_url).rstrip("/")
    current_user.avatar_url = f"{origin}/media/avatars/{name}"
    await db.commit()
    await db.refresh(current_user)
    return _serialize_user_response(
        current_user, await count_completed_lessons(db, current_user.id)
    )


_DELETE_NEEDS_SIGN_IN = "For your security, sign in again before deleting your account."


@router.delete("/me", response_model=MessageResponse)
async def delete_current_user(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Delete current user account.
    
    This is a soft delete (sets is_active to False).
    """
    ensure_recent_sign_in(current_user, _DELETE_NEEDS_SIGN_IN)
    await ensure_not_last_super_admin(db, current_user)
    current_user.is_active = False
    await revoke_all_refresh_tokens(db, current_user.id)
    await db.commit()
    await InactiveUserFlag.sync(current_user.id, False)
    
    return MessageResponse(
        message="Account deactivated successfully",
        detail="Your account has been deactivated. Contact support to reactivate."
    )


@router.delete("/me/permanent", response_model=MessageResponse)
async def permanently_delete_current_user(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """GDPR hard delete — removes all user data permanently."""
    ensure_recent_sign_in(current_user, _DELETE_NEEDS_SIGN_IN)
    await ensure_not_last_super_admin(db, current_user)
    user_id = current_user.id
    await permanently_delete_user(db, current_user)
    await db.commit()
    await InactiveUserFlag.sync(user_id, False)
    return MessageResponse(
        message="Account permanently deleted",
        detail="All user data has been permanently removed.",
    )


@router.get("/search", response_model=List[dict])
async def search_users(
    q: str = Query(..., min_length=1, max_length=100, description="Search query"),
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Search users by username or display_name."""
    users = await UserCRUD.search(db, q, exclude_id=current_user.id, limit=limit)
    user_ids = [u.id for u in users]
    following_set = await UserCRUD.get_following_ids(db, current_user.id, user_ids)

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


# =====================
# Level & Stats Endpoints
# =====================


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
        proficiency_level=rank_proficiency_level(current_user)
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
            certified_level=rank_proficiency_level(current_user),
            level_verified=level_verified(current_user),
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
async def get_user_stats_route(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    stats = await get_user_stats(db, current_user)
    return ApiResponse(success=True, data=stats, message="User stats retrieved successfully")


@router.get("/me/weekly-activity", response_model=ApiResponse[WeeklyActivityResponse])
async def get_weekly_activity_route(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    activity = await get_weekly_activity(db, current_user)
    return ApiResponse(success=True, data=activity, message="Weekly activity retrieved successfully")


@router.post("/me/start-learning", response_model=ApiResponse[StartLearningResponse])
async def start_learning(
    payload: StartLearningRequest | None = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Enroll in the best-fitting course and return the first lesson to play."""
    from app.routes.courses import enroll_in_course

    target = await find_start_target(
        db, current_user, payload.course_id if payload else None
    )
    if target is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No playable lesson is available yet",
        )
    already = await CourseCRUD.is_user_enrolled(db, current_user.id, target.course.id)
    if not already:
        await enroll_in_course(target.course.id, db=db, current_user=current_user)
    return ApiResponse(
        data=StartLearningResponse(
            course_id=target.course.id,
            course_title=target.course.title,
            first_lesson_id=target.lesson_id,
            already_enrolled=already,
        )
    )
