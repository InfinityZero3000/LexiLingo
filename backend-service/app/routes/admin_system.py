"""Admin routes — seed data, system info, and quota monitoring."""
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.config import settings
from app.core.dependencies import get_current_admin, get_current_super_admin
from app.models.user import User
from app.models.course import Course
from app.models.vocabulary import VocabularyItem
from app.models.gamification import Achievement
from app.schemas.response import ApiResponse
from app.services import admin_seed_service

router = APIRouter(prefix="/admin", tags=["Admin"])

require_admin = get_current_admin
require_super_admin = get_current_super_admin

# ============================================================================
# Seed Data Endpoint (Development Only)
# ============================================================================

@router.post("/seed", response_model=ApiResponse[dict])
async def seed_sample_data(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Seed sample data for development/testing.

    Creates sample achievements, shop items, course categories, and courses.
    Admin only endpoint.
    """
    if not settings.is_development:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    achievements_created = await admin_seed_service.seed_achievements(db)
    shop_items_created = await admin_seed_service.seed_shop_items(db)
    categories_created, category_ids = await admin_seed_service.seed_course_categories(db)
    courses_created, units_created, lessons_created = await admin_seed_service.seed_courses(
        db, category_ids
    )

    await db.commit()

    created = {
        "achievements": achievements_created,
        "shop_items": shop_items_created,
        "course_categories": categories_created,
        "courses": courses_created,
        "units": units_created,
        "lessons": lessons_created,
    }

    return ApiResponse(
        success=True,
        message=(
            "Seed data created: "
            f"{created['achievements']} achievements, "
            f"{created['shop_items']} shop items, "
            f"{created['course_categories']} categories, "
            f"{created['courses']} courses, "
            f"{created['units']} units, "
            f"{created['lessons']} lessons"
        ),
        data=created
    )


# ============================================================================
# System Settings / Info
# ============================================================================

@router.get("/system-info", response_model=ApiResponse[dict])
async def get_system_info(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """Get system configuration and stats. Admin only."""
    from app.core.config import settings as app_settings
    from app.models.user import User as UserModel

    # Count totals
    user_count = (await db.execute(select(func.count(UserModel.id)))).scalar() or 0
    course_count = (await db.execute(select(func.count(Course.id)))).scalar() or 0
    vocab_count = (await db.execute(select(func.count(VocabularyItem.id)))).scalar() or 0
    achievement_count = (await db.execute(select(func.count(Achievement.id)))).scalar() or 0

    return ApiResponse(
        success=True,
        message="System info",
        data={
            "app_name": app_settings.APP_NAME,
            "app_env": app_settings.APP_ENV,
            "debug": app_settings.DEBUG,
            "api_prefix": app_settings.API_V1_PREFIX,
            "log_level": app_settings.LOG_LEVEL,
            "token_expire_minutes": app_settings.ACCESS_TOKEN_EXPIRE_MINUTES,
            "refresh_token_days": app_settings.REFRESH_TOKEN_EXPIRE_DAYS,
            "cors_origins": app_settings.cors_origins,
            "ai_service_url": app_settings.AI_SERVICE_URL,
            "google_oauth": bool(app_settings.GOOGLE_CLIENT_ID),
            "firebase": bool(app_settings.FIREBASE_PROJECT_ID),
            "totals": {
                "users": user_count,
                "courses": course_count,
                "vocabulary": vocab_count,
                "achievements": achievement_count,
            }
        }
    )


from pydantic import BaseModel

class SystemInfoUpdate(BaseModel):
    app_name: Optional[str] = None
    debug: Optional[bool] = None
    log_level: Optional[str] = None
    token_expire_minutes: Optional[int] = None
    refresh_token_days: Optional[int] = None
    cors_origins: Optional[str] = None

@router.put("/system-info", response_model=ApiResponse[dict])
async def update_system_info(
    payload: SystemInfoUpdate,
    admin_user: User = Depends(require_super_admin)
):
    """Update system configuration. Super-admin only."""
    from app.core.config import settings as app_settings

    if payload.app_name is not None:
        app_settings.APP_NAME = payload.app_name
        
    if payload.debug is not None:
        app_settings.DEBUG = payload.debug
        
    if payload.log_level is not None:
        level = payload.log_level.upper()
        if level in ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]:
            app_settings.LOG_LEVEL = level
            
    if payload.token_expire_minutes is not None:
        app_settings.ACCESS_TOKEN_EXPIRE_MINUTES = payload.token_expire_minutes
        
    if payload.refresh_token_days is not None:
        app_settings.REFRESH_TOKEN_EXPIRE_DAYS = payload.refresh_token_days
        
    if payload.cors_origins is not None:
        app_settings.ALLOWED_ORIGINS = payload.cors_origins
        
    return ApiResponse(
        success=True,
        message="System configuration updated successfully",
        data={
            "app_name": app_settings.APP_NAME,
            "app_env": app_settings.APP_ENV,
            "debug": app_settings.DEBUG,
            "api_prefix": app_settings.API_V1_PREFIX,
            "log_level": app_settings.LOG_LEVEL,
            "token_expire_minutes": app_settings.ACCESS_TOKEN_EXPIRE_MINUTES,
            "refresh_token_days": app_settings.REFRESH_TOKEN_EXPIRE_DAYS,
            "cors_origins": app_settings.cors_origins,
            "ai_service_url": app_settings.AI_SERVICE_URL,
        }
    )


# ============================================================================
# User Admin (RBAC) - MOVED TO app/routes/user_management.py
# ============================================================================
# Legacy routes removed - use /api/v1/admin/users/* endpoints from user_management.py


# ============================================================================
# API Quota Monitoring (Phase 0 Infrastructure)
# ============================================================================

@router.get("/quota-usage", response_model=ApiResponse[dict])
async def get_quota_usage(
    api_name: Optional[str] = Query(None, description="Specific API to check"),
    admin_user: User = Depends(require_admin),
):
    """
    Get current API quota usage for all APIs or a specific one.
    
    Returns usage stats including threshold status, remaining budget,
    and time until daily reset.
    """
    from app.services.quota_manager import QuotaManager

    if api_name:
        if api_name not in QuotaManager.LIMITS:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Unknown API: {api_name}. "
                       f"Available: {list(QuotaManager.LIMITS.keys())}",
            )
        usage = await QuotaManager.get_usage(api_name)
        return ApiResponse(
            success=True,
            message=f"Quota usage for {api_name}",
            data=usage,
        )

    all_usage = await QuotaManager.get_all_usage()
    return ApiResponse(
        success=True,
        message=f"Quota usage for {len(all_usage)} APIs",
        data={
            "apis": all_usage,
            "reset_in": QuotaManager.get_reset_time(),
        },
    )


@router.post("/quota-reset/{api_name}", response_model=ApiResponse[dict])
async def reset_quota(
    api_name: str,
    admin_user: User = Depends(require_admin),
):
    """
    Manually reset quota counter for a specific API (emergency use).
    
    Use when: quota incorrectly tracked, or need to allow more requests
    after investigating an issue.
    """
    from app.services.quota_manager import QuotaManager

    if api_name not in QuotaManager.LIMITS:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown API: {api_name}. "
                   f"Available: {list(QuotaManager.LIMITS.keys())}",
        )

    success = await QuotaManager.reset_quota(api_name)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Redis unavailable, cannot reset quota.",
        )

    return ApiResponse(
        success=True,
        message=f"Quota reset for {api_name}",
        data=await QuotaManager.get_usage(api_name),
    )
