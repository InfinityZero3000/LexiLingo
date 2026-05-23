"""
Gamification API Routes
Phase 4: Endpoints for Achievements, Leaderboards, Shop, and Social Features
"""

from typing import Optional, List
from uuid import UUID
from datetime import datetime, timezone
from math import radians, sin, cos, sqrt, atan2
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_current_user_optional
from app.core.cache import (
    build_cache_key,
    compute_cache_version,
    delete_cached,
    get_cached,
    set_cached,
)
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
    ActivityFeedResponse, ActivityFeedItem, FriendSuggestionsResponse,
    LocationUpdateRequest, LocationUpdateResponse, NearbyUsersResponse
)
from app.schemas.response import ApiResponse
from app.services.rank_service import apply_rank_info_to_user, calculate_rank

router = APIRouter(prefix="/gamification", tags=["Gamification"])


SOCIAL_LOCATION_TTL_SECONDS = 6 * 60 * 60


def _social_location_key(user_id: UUID) -> str:
    return build_cache_key("social_location", user_id=str(user_id))


def _round_coarse(value: float) -> float:
    # 2 decimals ~= 1.1km. This keeps nearby useful while protecting privacy.
    return round(value, 2)


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    earth_radius_km = 6371.0
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    a = (
        sin(d_lat / 2) ** 2
        + cos(radians(lat1)) * cos(radians(lat2)) * sin(d_lon / 2) ** 2
    )
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earth_radius_km * c


# ============================================================================
# Achievements Endpoints
# ============================================================================

@router.get("/achievements", response_model=ApiResponse[List[AchievementResponse]])
async def get_all_achievements(
    response: Response,
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

    response.headers["X-Cache-Version"] = compute_cache_version(response_data)
    response.headers["X-Cache-Source"] = "origin"
    
    return ApiResponse(
        success=True,
        message="Achievements retrieved successfully",
        data=response_data
    )


@router.get("/achievements/me", response_model=ApiResponse[List[UserAchievementResponse]])
async def get_my_achievements(
    response: Response,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's unlocked achievements.
    
    Returns all achievements the user has earned with unlock dates.
    """
    cache_key = build_cache_key("achievements_me", user_id=str(current_user.id))
    cached = await get_cached(cache_key)
    if cached:
        response.headers["X-Cache-Version"] = compute_cache_version(cached)
        response.headers["X-Cache-Source"] = "redis"
        return ApiResponse(
            success=True,
            message=f"Retrieved {len(cached)} achievements",
            data=cached
        )
    
    user_achievements = await AchievementCRUD.get_user_achievements_with_details(db, current_user.id)
    
    response_data = []
    for ua, achievement in user_achievements:
        response_data.append({
            "id": ua.id,
            "achievement": AchievementResponse.model_validate(achievement).model_dump(mode="json"),
            "unlocked_at": ua.unlocked_at.isoformat() if ua.unlocked_at else None,
            "progress": ua.progress,
            "is_showcased": ua.is_showcased
        })
    
    await set_cached(cache_key, response_data, ttl=30)
    response.headers["X-Cache-Version"] = compute_cache_version(response_data)
    response.headers["X-Cache-Source"] = "origin"
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(response_data)} achievements",
        data=response_data
    )


@router.get("/achievements/recent", response_model=ApiResponse[List[UserAchievementResponse]])
async def get_recent_achievements(
    limit: int = Query(4, ge=1, le=10, description="Number of recent badges to return"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get user's most recently earned achievements.
    
    Following agent-skills/language-learning-patterns:
    - gamification-achievement-badges: Display recent badges for engagement (25-40% boost)
    
    Returns badges sorted by unlocked_at DESC, limited to specified count.
    Used for profile page "Recent Badges" section.
    """
    user_achievements = await AchievementCRUD.get_user_achievements_with_details(
        db, current_user.id, 
        order_by_recent=True, 
        limit=limit
    )
    
    response_data = []
    for ua, achievement in user_achievements:
        response_data.append({
            "id": ua.id,
            "achievement": AchievementResponse.model_validate(achievement),
            "unlocked_at": ua.unlocked_at,
            "progress": ua.progress,
            "is_showcased": ua.is_showcased
        })
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(response_data)} recent badges",
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

    await delete_cached(build_cache_key("achievements_me", user_id=str(current_user.id)))
    await delete_cached(build_cache_key("wallet", user_id=str(current_user.id)))
    
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
    cache_key = build_cache_key("wallet", user_id=str(current_user.id))
    cached = await get_cached(cache_key)
    if cached:
        return ApiResponse(
            success=True,
            message="Wallet retrieved successfully",
            data=cached
        )
    
    wallet = await WalletCRUD.get_or_create_wallet(db, current_user.id)
    wallet_data = WalletResponse.model_validate(wallet).model_dump(mode="json")
    await set_cached(cache_key, wallet_data, ttl=30)
    
    return ApiResponse(
        success=True,
        message="Wallet retrieved successfully",
        data=wallet_data
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
    response: Response,
    league: str = Query("bronze", description="Rank: bronze, silver, gold, platinum, diamond, master"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get weekly leaderboard for specific league.
    
    Returns top players in the league with XP earned this week.
    """
    normalized_league = league.lower().strip()
    await LeaderboardCRUD.sync_current_week_entries_to_user_rank(db)

    cache_key = build_cache_key("leaderboard", league=normalized_league, user_id=str(current_user.id))
    cached = await get_cached(cache_key)
    cached_entries = cached.get("entries", []) if isinstance(cached, dict) else []
    cached_matches_rank = (
        isinstance(cached, dict)
        and str(cached.get("league", "")).lower() == normalized_league
        and all(
            str(entry.get("user_rank", "")).lower() == normalized_league
            for entry in cached_entries
            if isinstance(entry, dict)
        )
    )
    if cached and cached_matches_rank:
        response.headers["X-Cache-Version"] = compute_cache_version(cached)
        response.headers["X-Cache-Source"] = "redis"
        return ApiResponse(
            success=True,
            message="Leaderboard retrieved successfully",
            data=cached
        )
    
    entries = await LeaderboardCRUD.get_leaderboard(db, league)
    week_start, week_end = LeaderboardCRUD.get_current_week_range()
    
    leaderboard_entries = []
    current_user_rank = None
    total_participants = await LeaderboardCRUD.count_rank_participants(
        db,
        normalized_league,
    )

    if not entries:
        fallback_users, fallback_total = await LeaderboardCRUD.get_leaderboard_from_users(
            db,
            normalized_league,
        )
        total_participants = fallback_total
        for rank, user in enumerate(fallback_users, 1):
            is_current = user.id == current_user.id
            if is_current:
                current_user_rank = rank

            leaderboard_entries.append(LeaderboardUserEntry(
                rank=rank,
                user_id=user.id,
                username=user.username,
                display_name=user.display_name,
                avatar_url=user.avatar_url,
                user_rank=user.rank,
                xp_earned=user.total_xp,
                lessons_completed=0,
                is_current_user=is_current,
            ))
    
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
            user_rank=user.rank,
            xp_earned=entry.xp_earned,
            lessons_completed=entry.lessons_completed,
            is_current_user=is_current
        ))

    if normalized_league == (current_user.rank or "bronze").lower():
        current_user_rank = await LeaderboardCRUD.get_user_rank(db, current_user.id)
        if not any(entry.user_id == current_user.id for entry in leaderboard_entries):
            current_entry = await LeaderboardCRUD.get_or_create_entry(
                db,
                current_user.id,
            )
            leaderboard_entries.append(LeaderboardUserEntry(
                rank=current_user_rank or len(leaderboard_entries) + 1,
                user_id=current_user.id,
                username=current_user.username,
                display_name=current_user.display_name,
                avatar_url=current_user.avatar_url,
                user_rank=current_user.rank,
                xp_earned=current_entry.xp_earned,
                lessons_completed=current_entry.lessons_completed,
                is_current_user=True,
            ))

    if not current_user_rank and total_participants > 0:
        current_user_rank = next(
            (entry.rank for entry in leaderboard_entries if entry.user_id == current_user.id),
            None,
        )
    
    leaderboard_data = LeaderboardResponse(
        league=normalized_league,
        week_start=week_start,
        week_end=week_end,
        entries=leaderboard_entries,
        current_user_rank=current_user_rank,
        total_participants=total_participants
    ).model_dump(mode="json")
    await set_cached(cache_key, leaderboard_data, ttl=30)
    response.headers["X-Cache-Version"] = compute_cache_version(leaderboard_data)
    response.headers["X-Cache-Source"] = "origin"
    
    return ApiResponse(
        success=True,
        message="Leaderboard retrieved successfully",
        data=leaderboard_data
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
    rank_info = calculate_rank(
        numeric_level=current_user.numeric_level or 1,
        proficiency_level=current_user.level or "A1",
    )
    apply_rank_info_to_user(current_user, rank_info)
    await db.commit()

    entry = await LeaderboardCRUD.get_or_create_entry(db, current_user.id)
    rank = await LeaderboardCRUD.get_user_rank(db, current_user.id)
    _, week_end = LeaderboardCRUD.get_current_week_range()
    
    hours_remaining = int((week_end - datetime.now(timezone.utc)).total_seconds() / 3600)
    
    return ApiResponse(
        success=True,
        message="League status retrieved successfully",
        data=UserLeagueStatusResponse(
            league=current_user.rank,
            rank_name=rank_info.name,
            rank_score=rank_info.score,
            rank_level_score=rank_info.level_score,
            rank_proficiency_score=rank_info.proficiency_score,
            total_xp=current_user.total_xp or 0,
            numeric_level=current_user.numeric_level or 1,
            proficiency_level=current_user.level or "A1",
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

    await delete_cached(build_cache_key("wallet", user_id=str(current_user.id)))
    
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
    inventory_items = await ShopCRUD.get_user_inventory_with_items(db, current_user.id)
    
    response_items = []
    for inv, item in inventory_items:
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


@router.post("/inventory/use", response_model=ApiResponse[UseItemResponse])
async def use_inventory_item(
    request: UseItemRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Use an item from inventory.
    
    Activates the item's effect (e.g., double XP, streak freeze).
    Decrements quantity and marks activation time if applicable.
    
    Item types and effects:
    - streak_freeze: Adds freeze protection to user's streak
    - double_xp: Activates 2x XP multiplier for specified duration
    - hint_pack: Adds hints to user's account
    - heart_refill: Restores lives/hearts to maximum
    """
    from app.services.item_effects_service import ItemEffectsService
    
    effects_service = ItemEffectsService(db)
    success, message, effects = await effects_service.use_item(
        current_user.id, request.inventory_id
    )
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=message
        )

    await delete_cached(build_cache_key("wallet", user_id=str(current_user.id)))
    
    return ApiResponse(
        success=True,
        message=message,
        data=UseItemResponse(
            success=True,
            effects_applied=effects,
            message=message
        )
    )


@router.get("/boosts/active", response_model=ApiResponse[List[dict]])
async def get_active_boosts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get all currently active boosts for the user.
    
    Returns active boosts with their effects and remaining time.
    Useful for displaying active buffs in the UI.
    """
    from app.services.item_effects_service import ItemEffectsService
    
    effects_service = ItemEffectsService(db)
    active_boosts = await effects_service.get_active_boosts(current_user.id)
    
    return ApiResponse(
        success=True,
        message=f"Found {len(active_boosts)} active boosts",
        data=active_boosts
    )


@router.get("/boosts/xp-multiplier", response_model=ApiResponse[dict])
async def get_xp_multiplier(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current XP multiplier for the user.
    
    Checks for active double_xp boosts and returns the multiplier.
    Returns 1.0 if no boost is active.
    """
    from app.services.item_effects_service import ItemEffectsService
    
    effects_service = ItemEffectsService(db)
    multiplier = await effects_service.get_xp_multiplier(current_user.id)
    
    return ApiResponse(
        success=True,
        message="XP multiplier retrieved",
        data={
            "multiplier": multiplier,
            "has_boost": multiplier > 1.0
        }
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

    if success:
        from app.models.notification import Notification
        follower_name = current_user.display_name or current_user.username or "Someone"
        notification = Notification(
            user_id=user_id,
            title="New Follower",
            body=f"{follower_name} started following you",
            type="social",
            data={"follower_id": str(current_user.id), "follower_username": follower_name},
        )
        db.add(notification)
        await db.commit()

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
    
    following_ids = await SocialCRUD.get_following_ids(
        db, current_user.id, [u.id for u in followers]
    )
    profiles = []
    for user in followers:
        profiles.append(UserSocialProfile(
            user_id=user.id,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            total_xp=user.total_xp,
            current_streak=0,
            league=user.rank,
            is_following=user.id in following_ids
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
    
    following_ids = await SocialCRUD.get_following_ids(
        db, current_user.id, [u.id for u in following]
    )
    profiles = []
    for user in following:
        profiles.append(UserSocialProfile(
            user_id=user.id,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            total_xp=user.total_xp,
            current_streak=0,
            league=user.rank,
            is_following=user.id in following_ids
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
            avatar_url=user.avatar_url,
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


@router.get("/users/suggestions", response_model=ApiResponse[FriendSuggestionsResponse])
async def get_friend_suggestions(
    limit: int = Query(10, ge=1, le=30),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get friend suggestions for the current user based on profile similarity."""
    suggestions = await SocialCRUD.get_friend_suggestions(db, current_user.id, limit, offset)

    users = [
        UserSocialProfile(
            user_id=user.id,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            total_xp=user.total_xp,
            current_streak=0,
            league=user.rank,
            is_following=False,
            mutual_connections=mutual_count,
            suggestion_reasons=reasons,
            similarity_score=score,
        )
        for user, score, mutual_count, reasons in suggestions
    ]

    return ApiResponse(
        success=True,
        message=f"Retrieved {len(users)} friend suggestions",
        data=FriendSuggestionsResponse(users=users, total=len(users)),
    )


@router.post("/users/location", response_model=ApiResponse[LocationUpdateResponse])
async def update_social_location(
    request: LocationUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Update nearby location sharing for current user using hybrid privacy model.

    - Stores only coarse location (rounded coordinates)
    - Uses short TTL to avoid persistent tracking
    - Allows explicit opt-out via enabled=false
    """
    _ = db
    location_key = _social_location_key(current_user.id)

    if not request.enabled:
        await delete_cached(location_key)
        return ApiResponse(
            success=True,
            message="Nearby location sharing disabled",
            data=LocationUpdateResponse(
                enabled=False,
                expires_in_seconds=0,
            ),
        )

    if request.latitude is None or request.longitude is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="latitude and longitude are required when enabled=true",
        )

    payload = {
        "user_id": str(current_user.id),
        "latitude": _round_coarse(request.latitude),
        "longitude": _round_coarse(request.longitude),
        "accuracy_meters": request.accuracy_meters,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    await set_cached(location_key, payload, ttl=SOCIAL_LOCATION_TTL_SECONDS)

    return ApiResponse(
        success=True,
        message="Nearby location sharing updated",
        data=LocationUpdateResponse(
            enabled=True,
            stored_latitude=payload["latitude"],
            stored_longitude=payload["longitude"],
            expires_in_seconds=SOCIAL_LOCATION_TTL_SECONDS,
        ),
    )


@router.get("/users/nearby", response_model=ApiResponse[NearbyUsersResponse])
async def get_nearby_users(
    limit: int = Query(10, ge=1, le=30),
    radius_km: float = Query(25.0, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get nearby learners from short-lived coarse location cache."""
    location_key = _social_location_key(current_user.id)
    current_location = await get_cached(location_key)
    if not current_location:
        return ApiResponse(
            success=True,
            message="Location sharing is disabled or expired",
            data=NearbyUsersResponse(
                users=[],
                total=0,
                radius_km=radius_km,
                location_enabled=False,
            ),
        )

    current_lat = float(current_location["latitude"])
    current_lon = float(current_location["longitude"])
    suggestions = await SocialCRUD.get_friend_suggestions(db, current_user.id, limit * 4)

    nearby_users: List[UserSocialProfile] = []
    for user, score, mutual_count, reasons in suggestions:
        user_location = await get_cached(_social_location_key(user.id))
        if not user_location:
            continue

        candidate_lat = float(user_location["latitude"])
        candidate_lon = float(user_location["longitude"])
        distance = _haversine_km(current_lat, current_lon, candidate_lat, candidate_lon)
        if distance > radius_km:
            continue

        suggestion_reasons = list(reasons)
        if "nearby" not in suggestion_reasons:
            suggestion_reasons.append("nearby")

        nearby_users.append(
            UserSocialProfile(
                user_id=user.id,
                username=user.username,
                display_name=user.display_name,
                avatar_url=user.avatar_url,
                total_xp=user.total_xp,
                current_streak=0,
                league=user.rank,
                is_following=False,
                mutual_connections=mutual_count,
                suggestion_reasons=suggestion_reasons,
                similarity_score=score,
                distance_km=round(distance, 2),
            )
        )

    nearby_users.sort(
        key=lambda p: (
            p.distance_km if p.distance_km is not None else 9999.0,
            -(p.similarity_score or 0.0),
        )
    )
    nearby_users = nearby_users[:limit]

    return ApiResponse(
        success=True,
        message=f"Retrieved {len(nearby_users)} nearby learners",
        data=NearbyUsersResponse(
            users=nearby_users,
            total=len(nearby_users),
            radius_km=radius_km,
            location_enabled=True,
        ),
    )


@router.post("/users/{user_id}/unfollow", response_model=ApiResponse[FollowResponse])
async def unfollow_user_compat(
    user_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Backward-compatible unfollow endpoint for clients still using POST."""
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
