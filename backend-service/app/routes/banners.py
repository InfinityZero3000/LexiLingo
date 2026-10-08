"""Banner API — public active-banner lookup plus admin CRUD."""

from typing import Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_admin, get_current_user_optional
from app.crud.banner import BannerCRUD
from app.models.user import User
from app.schemas.banner import (
    BannerCreate,
    BannerPublic,
    BannerResponse,
    BannerUpdate,
)
from app.schemas.common import ApiResponse
from app.services.entitlement_service import EntitlementService

router = APIRouter(prefix="/banners", tags=["Banners"])


# =====================
# Public endpoint
# =====================

@router.get("/active", response_model=ApiResponse[list[BannerPublic]])
async def get_active_banners(
    position: str = Query("hero", pattern="^(hero|sidebar|interstitial)$"),
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Active banners for the given slot, filtered by the caller's level/language.

    Anonymous callers only see untargeted banners (no level/language restriction).
    Premium is ad-free: a confirmed subscription skips the lookup entirely.
    """
    if current_user and await EntitlementService.is_active(db, current_user.id):
        return ApiResponse(success=True, data=[])

    level = current_user.level if current_user else None
    language = current_user.target_language if current_user else None

    banners = await BannerCRUD.list_active(
        db, position=position, level=level, language=language
    )
    return ApiResponse(
        success=True,
        data=[BannerPublic.model_validate(b) for b in banners],
    )


# =====================
# Admin endpoints
# =====================

@router.get("", response_model=ApiResponse[list[BannerResponse]])
async def list_banners(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    banners = await BannerCRUD.list_all(db, skip=skip, limit=limit)
    return ApiResponse(success=True, data=[BannerResponse.model_validate(b) for b in banners])


@router.get("/{banner_id}", response_model=ApiResponse[BannerResponse])
async def get_banner(
    banner_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    banner = await BannerCRUD.get_by_id(db, banner_id)
    if not banner:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Banner not found")
    return ApiResponse(success=True, data=BannerResponse.model_validate(banner))


@router.post("", response_model=ApiResponse[BannerResponse], status_code=status.HTTP_201_CREATED)
async def create_banner(
    payload: BannerCreate,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    banner = await BannerCRUD.create(db, created_by_id=admin.id, **payload.model_dump())
    return ApiResponse(success=True, data=BannerResponse.model_validate(banner))


@router.put("/{banner_id}", response_model=ApiResponse[BannerResponse])
async def update_banner(
    banner_id: uuid.UUID,
    payload: BannerUpdate,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    banner = await BannerCRUD.update(db, banner_id, **payload.model_dump(exclude_unset=True))
    if not banner:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Banner not found")
    return ApiResponse(success=True, data=BannerResponse.model_validate(banner))


@router.delete("/{banner_id}", response_model=ApiResponse[dict])
async def delete_banner(
    banner_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    deleted = await BannerCRUD.delete(db, banner_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Banner not found")
    return ApiResponse(success=True, data={"id": str(banner_id)})
