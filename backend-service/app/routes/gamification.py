"""
Gamification API Routes
Phase 4: Endpoints for Achievements, Leaderboards, Shop, and Social Features
"""

from typing import Optional, List
from uuid import UUID
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_current_user_optional
from app.models.user import User
from app.crud.gamification import (
    AchievementCRUD, WalletCRUD, LeaderboardCRUD, ShopCRUD, SocialCRUD
)
from app.schemas.gamification import (
    AchievementResponse, AchievementProgressResponse, UserAchievementResponse,
    WalletResponse, WalletHistoryResponse, WalletTransactionResponse,
    LeaderboardResponse, LeaderboardUserEntry, UserLeagueStatusResponse,
    ShopItemResponse, PurchaseRequest, PurchaseResponse,
    InventoryResponse, UserInventoryItemResponse, UseItemRequest, UseItemResponse,
    FollowRequest, FollowResponse, UserSocialProfile, FollowersListResponse,
    ActivityFeedResponse, ActivityFeedItem
)
from app.schemas.response import ApiResponse

router = APIRouter(prefix="/gamification", tags=["Gamification"])


# ============================================================================
# Achievements Endpoints
# ============================================================================

@router.get("/achievements", response_model=ApiResponse[List[AchievementResponse]])
async def get_all_achievements(
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional)
):
    """
    Get all available achievements.
    
    Returns all achievement definitions. If authenticated, includes
    unlock status for the current user.
    """
    achievements = await AchievementCRUD.get_all_achievements(db)
    
    response_data = []
    for achievement in achievements:
        response_data.append(AchievementResponse.model_validate(achievement))
    
    return ApiResponse(
        success=True,
        message="Achievements retrieved successfully",
        data=response_data
    )


@router.get("/achievements/me", response_model=ApiResponse[List[UserAchievementResponse]])
async def get_my_achievements(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's unlocked achievements.
    
    Returns all achievements the user has earned with unlock dates.
    """
    user_achievements = await AchievementCRUD.get_user_achievements(db, current_user.id)
    
    response_data = []
    for ua in user_achievements:
        # Get the achievement details
        achievement = await AchievementCRUD.get_achievement(db, ua.achievement_id)
        if achievement:
            response_data.append({
                "id": ua.id,
                "achievement": AchievementResponse.model_validate(achievement),
                "unlocked_at": ua.unlocked_at,
                "progress": ua.progress,
                "is_showcased": ua.is_showcased
            })
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(response_data)} achievements",
        data=response_data
    )


@router.post("/achievements/check", response_model=ApiResponse[List[dict]])
async def check_all_achievements(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Force check all achievements for current user.
    
    Evaluates all achievement conditions and unlocks any that are met.
    Useful for catching up on achievements that might have been missed.
    
    Returns list of newly unlocked achievements.
    """
    from app.services import AchievementCheckerService
    
    checker = AchievementCheckerService(db)
    unlocked = await checker.check_all(current_user.id)
    
    response_data = [
        {
            "id": str(a.id),
            "name": a.name,
            "description": a.description,
            "badge_icon": a.badge_icon,
            "badge_color": a.badge_color,
            "category": a.category,
            "rarity": a.rarity,
            "xp_reward": a.xp_reward,
            "gems_reward": a.gems_reward,
        }
        for a in unlocked
    ]
    
    return ApiResponse(
        success=True,
        message=f"Checked all achievements. Unlocked {len(response_data)} new badges!",
        data=response_data
    )


# ============================================================================
# Wallet Endpoints
# ============================================================================

@router.get("/wallet", response_model=ApiResponse[WalletResponse])
async def get_my_wallet(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's wallet balance.
    
    Returns gem balance and totals.
    """
    wallet = await WalletCRUD.get_or_create_wallet(db, current_user.id)
    
    return ApiResponse(
        success=True,
        message="Wallet retrieved successfully",
        data=WalletResponse.model_validate(wallet)
    )


@router.get("/wallet/history", response_model=ApiResponse[List[WalletTransactionResponse]])
async def get_wallet_history(
    limit: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get wallet transaction history.
    
    Returns recent transactions (earn, spend, rewards).
    """
    transactions = await WalletCRUD.get_transactions(db, current_user.id, limit)
    
    response_data = [
        WalletTransactionResponse.model_validate(t) for t in transactions
    ]
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(response_data)} transactions",
        data=response_data
    )


# ============================================================================
# Leaderboard Endpoints
# ============================================================================

@router.get("/leaderboard", response_model=ApiResponse[LeaderboardResponse])
async def get_leaderboard(
    league: str = Query("bronze", description="League: bronze, silver, gold, platinum, diamond"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get weekly leaderboard for specific league.
    
    Returns top players in the league with XP earned this week.
    """
    entries = await LeaderboardCRUD.get_leaderboard(db, league)
    week_start, week_end = LeaderboardCRUD.get_current_week_range()
    
    leaderboard_entries = []
    current_user_rank = None
    
    for rank, (entry, user) in enumerate(entries, 1):
        is_current = entry.user_id == current_user.id
        if is_current:
            current_user_rank = rank
        
        leaderboard_entries.append(LeaderboardUserEntry(
            rank=rank,
            user_id=user.id,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url if hasattr(user, 'avatar_url') else None,
            xp_earned=entry.xp_earned,
            lessons_completed=entry.lessons_completed,
            is_current_user=is_current
        ))
    
    return ApiResponse(
        success=True,
        message="Leaderboard retrieved successfully",
        data=LeaderboardResponse(
            league=league,
            week_start=week_start,
            week_end=week_end,
            entries=leaderboard_entries,
            current_user_rank=current_user_rank,
            total_participants=len(leaderboard_entries)
        )
    )


@router.get("/leaderboard/me", response_model=ApiResponse[UserLeagueStatusResponse])
async def get_my_league_status(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's league status.
    
    Returns league, rank, and promotion/demotion zone status.
    """
    entry = await LeaderboardCRUD.get_or_create_entry(db, current_user.id)
    rank = await LeaderboardCRUD.get_user_rank(db, current_user.id)
    _, week_end = LeaderboardCRUD.get_current_week_range()
    
    hours_remaining = int((week_end - datetime.utcnow()).total_seconds() / 3600)
    
    return ApiResponse(
        success=True,
        message="League status retrieved successfully",
        data=UserLeagueStatusResponse(
            league=entry.league,
            current_rank=rank,
            xp_earned=entry.xp_earned,
            lessons_completed=entry.lessons_completed,
            is_in_promotion_zone=rank <= 3 if rank else False,
            is_in_demotion_zone=False,  # TODO: Implement based on league size
            week_ends_in_hours=max(0, hours_remaining)
        )
    )


# ============================================================================
# Shop Endpoints
# ============================================================================

@router.get("/shop", response_model=ApiResponse[List[ShopItemResponse]])
async def get_shop_items(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get all available shop items.
    
    Returns items that can be purchased with gems.
    """
    items = await ShopCRUD.get_available_items(db)
    
    response_data = [ShopItemResponse.model_validate(item) for item in items]
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(response_data)} shop items",
        data=response_data
    )


@router.post("/shop/purchase", response_model=ApiResponse[PurchaseResponse])
async def purchase_item(
    request: PurchaseRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Purchase an item from the shop.
    
    Spends gems and adds item to inventory.
    """
    inventory, message = await ShopCRUD.purchase_item(
        db, current_user.id, request.item_id, request.quantity
    )
    
    if not inventory:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=message
        )
    
    item = await ShopCRUD.get_item(db, request.item_id)
    wallet = await WalletCRUD.get_or_create_wallet(db, current_user.id)
    
    return ApiResponse(
        success=True,
        message="Purchase successful",
        data=PurchaseResponse(
            success=True,
            item=ShopItemResponse.model_validate(item),
            quantity=request.quantity,
            total_cost=item.price_gems * request.quantity,
            new_balance=wallet.gems,
            message=message
        )
    )


@router.get("/inventory", response_model=ApiResponse[InventoryResponse])
async def get_my_inventory(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's inventory.
    
    Returns all purchased items with quantities.
    """
    inventory_items = await ShopCRUD.get_user_inventory(db, current_user.id)
    
    response_items = []
    for inv in inventory_items:
        item = await ShopCRUD.get_item(db, inv.shop_item_id)
        if item:
            response_items.append(UserInventoryItemResponse(
                id=inv.id,
                item=ShopItemResponse.model_validate(item),
                quantity=inv.quantity,
                is_active=inv.is_active,
                activated_at=inv.activated_at,
                expires_at=inv.expires_at,
                purchased_at=inv.purchased_at
            ))
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(response_items)} inventory items",
        data=InventoryResponse(
            items=response_items,
            total_items=len(response_items)
        )
    )


# ============================================================================
# Social Endpoints
# ============================================================================

@router.post("/users/{user_id}/follow", response_model=ApiResponse[FollowResponse])
async def follow_user(
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Follow a user.
    
    Creates a following relationship between current user and target user.
    """
    success, message = await SocialCRUD.follow_user(db, current_user.id, user_id)
    
    return ApiResponse(
        success=success,
        message=message,
        data=FollowResponse(
            success=success,
            is_following=success,
            message=message
        )
    )


@router.delete("/users/{user_id}/follow", response_model=ApiResponse[FollowResponse])
async def unfollow_user(
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Unfollow a user.
    
    Removes the following relationship.
    """
    success, message = await SocialCRUD.unfollow_user(db, current_user.id, user_id)
    
    return ApiResponse(
        success=success,
        message=message,
        data=FollowResponse(
            success=success,
            is_following=not success,
            message=message
        )
    )


@router.get("/users/{user_id}/followers", response_model=ApiResponse[FollowersListResponse])
async def get_user_followers(
    user_id: UUID,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get a user's followers.
    
    Returns list of users following the specified user.
    """
    followers, total = await SocialCRUD.get_followers(db, user_id, limit, offset)
    
    profiles = []
    for user in followers:
        is_following = await SocialCRUD.is_following(db, current_user.id, user.id)
        profiles.append(UserSocialProfile(
            user_id=user.id,
            username=user.username,
            display_name=user.display_name,
            is_following=is_following
        ))
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(profiles)} followers",
        data=FollowersListResponse(users=profiles, total=total)
    )


@router.get("/users/{user_id}/following", response_model=ApiResponse[FollowersListResponse])
async def get_user_following(
    user_id: UUID,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get users that a user is following.
    
    Returns list of users the specified user follows.
    """
    following, total = await SocialCRUD.get_following(db, user_id, limit, offset)
    
    profiles = []
    for user in following:
        is_following = await SocialCRUD.is_following(db, current_user.id, user.id)
        profiles.append(UserSocialProfile(
            user_id=user.id,
            username=user.username,
            display_name=user.display_name,
            is_following=is_following
        ))
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(profiles)} following",
        data=FollowersListResponse(users=profiles, total=total)
    )


@router.get("/feed", response_model=ApiResponse[ActivityFeedResponse])
async def get_activity_feed(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get social activity feed.
    
    Returns activities from followed users and own activities.
    """
    activities = await SocialCRUD.get_activity_feed(
        db, current_user.id, limit, offset
    )
    
    feed_items = []
    for activity, user in activities:
        feed_items.append(ActivityFeedItem(
            id=activity.id,
            user_id=user.id,
            username=user.username,
            display_name=user.display_name,
            activity_type=activity.activity_type,
            message=activity.message,
            activity_data=activity.activity_data,
            created_at=activity.created_at
        ))
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(feed_items)} activities",
        data=ActivityFeedResponse(
            activities=feed_items,
            total=len(feed_items),
            has_more=len(feed_items) == limit
        )
    )
