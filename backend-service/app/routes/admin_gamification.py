"""Admin routes — achievements and shop items."""
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status, UploadFile, File
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_admin
from app.models.user import User
from app.models.gamification import Achievement, ShopItem
from app.schemas.response import ApiResponse
from app.schemas.gamification import ShopItemAdminCreate, ShopItemAdminUpdate

router = APIRouter(prefix="/admin", tags=["Admin"])

require_admin = get_current_admin

# ============================================================================
# Achievement Admin CRUD
# ============================================================================

@router.get("/achievements", response_model=ApiResponse[List[dict]])
async def list_achievements_admin(
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    List all achievements (admin view).
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(Achievement).order_by(Achievement.category, Achievement.name)
    )
    achievements = result.scalars().all()
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(achievements)} achievements",
        data=[{
            "id": str(a.id),
            "slug": a.slug,
            "name": a.name,
            "description": a.description,
            "badge_icon": a.badge_icon,
            "badge_color": a.badge_color,
            "condition_type": a.condition_type,
            "condition_value": a.condition_value,
            "category": a.category,
            "rarity": a.rarity,
            "xp_reward": a.xp_reward,
            "gems_reward": a.gems_reward,
            "is_hidden": a.is_hidden
        } for a in achievements]
    )


@router.post("/achievements", response_model=ApiResponse[dict])
async def create_achievement(
    name: str,
    description: str,
    condition_type: str,
    condition_value: int = 1,
    category: str = "special",
    rarity: str = "common",
    xp_reward: int = 0,
    gems_reward: int = 0,
    is_hidden: bool = False,
    badge_icon: Optional[str] = None,
    badge_color: Optional[str] = None,
    slug: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new achievement.
    
    Admin only endpoint.
    """
    achievement = Achievement(
        name=name,
        slug=slug,
        description=description,
        condition_type=condition_type,
        condition_value=condition_value,
        category=category,
        rarity=rarity,
        xp_reward=xp_reward,
        gems_reward=gems_reward,
        is_hidden=is_hidden,
        badge_icon=badge_icon,
        badge_color=badge_color
    )
    db.add(achievement)
    await db.commit()
    await db.refresh(achievement)
    
    return ApiResponse(
        success=True,
        message="Achievement created successfully",
        data={
            "id": str(achievement.id),
            "name": achievement.name,
            "category": achievement.category
        }
    )


@router.put("/achievements/{achievement_id}", response_model=ApiResponse[dict])
async def update_achievement(
    achievement_id: UUID,
    name: Optional[str] = None,
    description: Optional[str] = None,
    condition_type: Optional[str] = None,
    condition_value: Optional[int] = None,
    category: Optional[str] = None,
    rarity: Optional[str] = None,
    xp_reward: Optional[int] = None,
    gems_reward: Optional[int] = None,
    is_hidden: Optional[bool] = None,
    badge_icon: Optional[str] = None,
    badge_color: Optional[str] = None,
    slug: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """Update an achievement. Admin only."""
    result = await db.execute(
        select(Achievement).where(Achievement.id == achievement_id)
    )
    achievement = result.scalar_one_or_none()
    if not achievement:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Achievement not found")

    for field, value in {
        "name": name, "description": description, "condition_type": condition_type,
        "condition_value": condition_value, "category": category, "rarity": rarity,
        "xp_reward": xp_reward, "gems_reward": gems_reward, "is_hidden": is_hidden,
        "badge_icon": badge_icon, "badge_color": badge_color, "slug": slug,
    }.items():
        if value is not None:
            setattr(achievement, field, value)

    await db.commit()
    await db.refresh(achievement)

    return ApiResponse(
        success=True,
        message="Achievement updated successfully",
        data={
            "id": str(achievement.id),
            "name": achievement.name,
            "category": achievement.category,
            "rarity": achievement.rarity,
        }
    )


@router.delete("/achievements/{achievement_id}", response_model=ApiResponse[dict])
async def delete_achievement(
    achievement_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete an achievement.
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(Achievement).where(Achievement.id == achievement_id)
    )
    achievement = result.scalar_one_or_none()
    
    if not achievement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Achievement not found"
        )
    
    await db.delete(achievement)
    await db.commit()
    
    return ApiResponse(
        success=True,
        message="Achievement deleted successfully",
        data={"deleted": True, "achievement_id": str(achievement_id)}
    )


# ============================================================================
# Shop Admin CRUD
# ============================================================================

@router.get("/shop", response_model=ApiResponse[List[dict]])
async def list_shop_items_admin(
    include_unavailable: bool = Query(False),
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    List all shop items (admin view).
    
    Admin only endpoint.
    """
    query = select(ShopItem).order_by(ShopItem.item_type, ShopItem.price_gems)
    if not include_unavailable:
        query = query.where(ShopItem.is_available == True)
    
    result = await db.execute(query)
    items = result.scalars().all()
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(items)} shop items",
        data=[{
            "id": str(item.id),
            "name": item.name,
            "description": item.description,
            "item_type": item.item_type,
            "price_gems": item.price_gems,
            "icon_url": item.icon_url,
            "effects": item.effects,
            "is_available": item.is_available,
            "stock_quantity": item.stock_quantity
        } for item in items]
    )


@router.post("/shop", response_model=ApiResponse[dict])
async def create_shop_item(
    payload: ShopItemAdminCreate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Create a new shop item.

    Admin only endpoint.
    """
    item = ShopItem(
        name=payload.name,
        description=payload.description,
        item_type=payload.item_type,
        price_gems=payload.price_gems,
        icon_url=payload.icon_url,
        effects=payload.effects,
        is_available=payload.is_available,
        stock_quantity=payload.stock_quantity
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)

    return ApiResponse(
        success=True,
        message="Shop item created successfully",
        data={
            "id": str(item.id),
            "name": item.name,
            "price_gems": item.price_gems
        }
    )


@router.put("/shop/{item_id}", response_model=ApiResponse[dict])
async def update_shop_item(
    item_id: UUID,
    payload: ShopItemAdminUpdate,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Update a shop item.

    Admin only endpoint.
    """
    result = await db.execute(
        select(ShopItem).where(ShopItem.id == item_id)
    )
    item = result.scalar_one_or_none()

    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shop item not found"
        )

    if payload.name is not None:
        item.name = payload.name
    if payload.description is not None:
        item.description = payload.description
    if payload.item_type is not None:
        item.item_type = payload.item_type
    if payload.price_gems is not None:
        item.price_gems = payload.price_gems
    if payload.icon_url is not None:
        item.icon_url = payload.icon_url
    if payload.effects is not None:
        item.effects = payload.effects
    if payload.is_available is not None:
        item.is_available = payload.is_available
    if payload.stock_quantity is not None:
        item.stock_quantity = payload.stock_quantity

    await db.commit()
    await db.refresh(item)

    return ApiResponse(
        success=True,
        message="Shop item updated successfully",
        data={
            "id": str(item.id),
            "name": item.name,
            "price_gems": item.price_gems,
            "is_available": item.is_available
        }
    )


@router.delete("/shop/{item_id}", response_model=ApiResponse[dict])
async def delete_shop_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_admin)
):
    """
    Delete a shop item.
    
    Admin only endpoint.
    """
    result = await db.execute(
        select(ShopItem).where(ShopItem.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shop item not found"
        )
    
    await db.delete(item)
    await db.commit()
    
    return ApiResponse(
        success=True,
        message="Shop item deleted successfully",
        data={"deleted": True, "item_id": str(item_id)}
    )


