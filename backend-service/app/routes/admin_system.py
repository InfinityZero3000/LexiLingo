"""Admin routes — seed data, system info, and quota monitoring."""
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.config import settings
from app.core.dependencies import get_current_admin, get_current_super_admin, require_permission
from app.models.user import User
from app.models.course import Course
from app.models.vocabulary import VocabularyItem
from app.models.gamification import Achievement
from app.schemas.response import ApiResponse
from app.services import admin_seed_service
from app.services.admin_audit import record_admin_action

router = APIRouter(prefix="/admin", tags=["Admin"])

require_admin = get_current_admin
require_super_admin = get_current_super_admin

# ============================================================================
# Seed Data Endpoint (Development Only)
# ============================================================================

@router.post("/seed", response_model=ApiResponse[dict])
async def seed_sample_data(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_super_admin)
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

async def _migration_state(db: AsyncSession) -> dict:
    """What the database is at versus what the code ships; either side may be unknown."""
    from pathlib import Path

    from sqlalchemy import text

    current: list[str] | None
    try:
        current = sorted((await db.execute(text("SELECT version_num FROM alembic_version"))).scalars().all())
    except Exception:
        await db.rollback()
        current = None
    heads: list[str] | None
    try:
        from alembic.config import Config
        from alembic.script import ScriptDirectory

        config = Config()
        config.set_main_option("script_location", str(Path(__file__).resolve().parents[2] / "alembic"))
        heads = sorted(ScriptDirectory.from_config(config).get_heads())
    except Exception:
        heads = None
    return {
        "current": current,
        "head": heads,
        "up_to_date": (current == heads) if current is not None and heads is not None else None,
    }


@router.get("/system-info", response_model=ApiResponse[dict])
async def get_system_info(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_permission("ops:read"))
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
            "migration": await _migration_state(db),
            "totals": {
                "users": user_count,
                "courses": course_count,
                "vocabulary": vocab_count,
                "achievements": achievement_count,
            }
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
    admin_user: User = Depends(require_permission("ops:read")),
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
    request: Request,
    admin_user: User = Depends(require_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Manually reset quota counter for a specific API (emergency use).
    
    Use when: quota incorrectly tracked, or need to allow more requests
    after investigating an issue. Super admin only, and audited: it lifts a
    cost-protection limit.
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

    record_admin_action(db, admin_user, "quota_reset", "quota", api_name, {"api": api_name}, request)
    await db.commit()

    return ApiResponse(
        success=True,
        message=f"Quota reset for {api_name}",
        data=await QuotaManager.get_usage(api_name),
    )
