"""
Gamification Schemas
Phase 4: Schemas for Achievements, Leaderboards, Shop, and Social Features
"""

from datetime import datetime
from typing import Optional, List, Dict, Any
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field
from enum import Enum


# ============================================================================
# Enums
# ============================================================================

class League(str, Enum):
    """Leaderboard leagues"""
    BRONZE = "bronze"
    SILVER = "silver"
    GOLD = "gold"
    PLATINUM = "platinum"
    SAPPHIRE = "sapphire"
    RUBY = "ruby"
    AMETHYST = "amethyst"
    MASTER = "master"


class AchievementCategory(str, Enum):
    """Achievement categories"""
    STREAK = "streak"
    LESSONS = "lessons"
    VOCABULARY = "vocabulary"
    SOCIAL = "social"
    SPECIAL = "special"


class AchievementRarity(str, Enum):
    """Achievement rarity levels"""
    COMMON = "common"
    RARE = "rare"
    EPIC = "epic"
    LEGENDARY = "legendary"


class TransactionType(str, Enum):
    """Wallet transaction types"""
    EARN = "earn"
    SPEND = "spend"
    PURCHASE = "purchase"
    REWARD = "reward"
    REFUND = "refund"


# ============================================================================
# Achievement Schemas
# ============================================================================

class AchievementBase(BaseModel):
    """Base achievement schema"""
    name: str
    description: str
    category: Optional[str] = None
    rarity: str = "common"
    xp_reward: int = 0
    gems_reward: int = 0


class AchievementResponse(AchievementBase):
    """Achievement response"""
    id: UUID
    slug: Optional[str] = None
    badge_icon: Optional[str] = None
    badge_color: Optional[str] = None
    condition_type: Optional[str] = None
    condition_value: Optional[int] = None
    is_hidden: bool = False
    created_at: datetime
    
    model_config = ConfigDict(from_attributes=True)


class UserAchievementResponse(BaseModel):
    """User's unlocked achievement"""
    id: UUID
    achievement: AchievementResponse
    unlocked_at: datetime
    progress: int = 0
    is_showcased: bool = False
    
    model_config = ConfigDict(from_attributes=True)


class AchievementProgressResponse(BaseModel):
    """Achievement progress for user"""
    achievement_id: UUID
    name: str
    description: str
    category: Optional[str] = None
    rarity: str
    badge_icon: Optional[str] = None
    is_unlocked: bool = False
    progress: int = 0
    target: int = 0
    progress_percentage: float = 0.0
    unlocked_at: Optional[datetime] = None
    
    model_config = ConfigDict(from_attributes=True)


# ============================================================================
# Wallet Schemas
# ============================================================================

class WalletResponse(BaseModel):
    """User wallet response"""
    id: UUID
    user_id: UUID
    gems: int
    total_gems_earned: int
    total_gems_spent: int
    updated_at: datetime
    
    model_config = ConfigDict(from_attributes=True)


class WalletTransactionResponse(BaseModel):
    """Wallet transaction"""
    id: UUID
    transaction_type: str
    amount: int
    balance_after: int
    source: Optional[str] = None
    description: Optional[str] = None
    created_at: datetime
    
    model_config = ConfigDict(from_attributes=True)


class StarterRewardResponse(BaseModel):
    reward_key: str
    gems_awarded: int
    current_balance: int
    title: str
    body: str


class WalletHistoryResponse(BaseModel):
    """Wallet with transaction history"""
    wallet: WalletResponse
    transactions: List[WalletTransactionResponse]
    
    model_config = ConfigDict(from_attributes=True)


# ============================================================================
# Leaderboard Schemas
# ============================================================================

class LeaderboardUserEntry(BaseModel):
    """Individual leaderboard entry"""
    rank: int
    user_id: UUID
    username: str
    display_name: Optional[str] = None
    avatar_url: Optional[str] = None
    user_rank: str = "bronze"
    xp_earned: int
    lessons_completed: int
    is_current_user: bool = False
    
    model_config = ConfigDict(from_attributes=True)


class LeaderboardResponse(BaseModel):
    """Weekly leaderboard"""
    league: str
    week_start: datetime
    week_end: datetime
    entries: List[LeaderboardUserEntry]
    current_user_rank: Optional[int] = None
    total_participants: int
    promotion_zone: int = 3  # Top N get promoted
    demotion_zone: int = 3   # Bottom N get demoted
    
    model_config = ConfigDict(from_attributes=True)


class UserLeagueStatusResponse(BaseModel):
    """User's current league status"""
    league: str
    rank_name: str = "Bronze"
    rank_score: float = 0.0
    rank_level_score: float = 0.0
    rank_proficiency_score: float = 0.0
    total_xp: int = 0
    numeric_level: int = 1
    proficiency_level: str = "A1"
    current_rank: Optional[int] = None
    xp_earned: int
    lessons_completed: int
    is_in_promotion_zone: bool = False
    is_in_demotion_zone: bool = False
    week_ends_in_hours: int
    rank_icon_url: str = ""
    
    model_config = ConfigDict(from_attributes=True)


# ============================================================================
# Shop Schemas
# ============================================================================

class ShopItemResponse(BaseModel):
    """Shop item"""
    id: UUID
    name: str
    description: str
    item_type: str
    price_gems: int
    icon_url: Optional[str] = None
    effects: Optional[Dict[str, Any]] = None
    is_available: bool = True
    stock_quantity: Optional[int] = None
    
    model_config = ConfigDict(from_attributes=True)


class ShopItemAdminCreate(BaseModel):
    """Admin payload to create a shop item, including effects/icon_url."""
    name: str
    description: str
    item_type: str
    price_gems: int
    icon_url: Optional[str] = None
    effects: Optional[Dict[str, Any]] = None
    is_available: bool = True
    stock_quantity: Optional[int] = None


class ShopItemAdminUpdate(BaseModel):
    """Admin payload to update a shop item. All fields optional (partial update)."""
    name: Optional[str] = None
    description: Optional[str] = None
    item_type: Optional[str] = None
    price_gems: Optional[int] = None
    icon_url: Optional[str] = None
    effects: Optional[Dict[str, Any]] = None
    is_available: Optional[bool] = None
    stock_quantity: Optional[int] = None


class PurchaseRequest(BaseModel):
    """Purchase request"""
    item_id: UUID
    quantity: int = 1


class PurchaseResponse(BaseModel):
    """Purchase result"""
    success: bool
    item: ShopItemResponse
    quantity: int
    total_cost: int
    new_balance: int
    message: str
    
    model_config = ConfigDict(from_attributes=True)


class EquipAvatarRequest(BaseModel):
    """Equip an avatar owned in the user's inventory."""
    inventory_id: UUID


class EquipAvatarResponse(BaseModel):
    """Result of equipping a permanent avatar cosmetic."""
    avatar_url: str
    inventory_id: UUID


class UserInventoryItemResponse(BaseModel):
    """User's inventory item"""
    id: UUID
    item: ShopItemResponse
    quantity: int
    is_active: bool = False
    activated_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    purchased_at: datetime
    
    model_config = ConfigDict(from_attributes=True)


class InventoryResponse(BaseModel):
    """User's full inventory"""
    items: List[UserInventoryItemResponse]
    total_items: int
    
    model_config = ConfigDict(from_attributes=True)


class UseItemRequest(BaseModel):
    """Request to use/activate an item"""
    inventory_id: UUID


class UseItemResponse(BaseModel):
    """Result of using an item"""
    success: bool
    message: str
    item_name: str
    effects_applied: Optional[Dict[str, Any]] = None
    expires_at: Optional[datetime] = None
    
    model_config = ConfigDict(from_attributes=True)


# ============================================================================
# Social Schemas
# ============================================================================

class FollowRequest(BaseModel):
    """Follow/Unfollow request"""
    user_id: UUID


class FollowResponse(BaseModel):
    """Follow result"""
    success: bool
    is_following: bool
    message: str


class UserSocialProfile(BaseModel):
    """User's social profile"""
    user_id: UUID
    username: str
    display_name: Optional[str] = None
    avatar_url: Optional[str] = None
    total_xp: int = 0
    current_streak: int = 0
    league: str = "bronze"
    achievements_count: int = 0
    is_following: Optional[bool] = None  # Only for authenticated user
    mutual_connections: int = 0
    suggestion_reasons: List[str] = Field(default_factory=list)
    similarity_score: Optional[float] = None
    distance_km: Optional[float] = None
    
    model_config = ConfigDict(from_attributes=True)


class FollowersListResponse(BaseModel):
    """List of followers/following"""
    users: List[UserSocialProfile]
    total: int
    
    model_config = ConfigDict(from_attributes=True)


class FriendSuggestionsResponse(BaseModel):
    """Friend suggestions payload"""
    users: List[UserSocialProfile]
    total: int

    model_config = ConfigDict(from_attributes=True)


class LocationUpdateRequest(BaseModel):
    """Hybrid location update request (coarse + optional consent)."""
    enabled: bool = True
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    accuracy_meters: Optional[float] = Field(default=None, ge=0)


class LocationUpdateResponse(BaseModel):
    """Stored location sharing status for social nearby feature."""
    enabled: bool
    stored_latitude: Optional[float] = None
    stored_longitude: Optional[float] = None
    expires_in_seconds: int = 0

    model_config = ConfigDict(from_attributes=True)


class NearbyUsersResponse(BaseModel):
    """Nearby learners payload."""
    users: List[UserSocialProfile]
    total: int
    radius_km: float
    location_enabled: bool

    model_config = ConfigDict(from_attributes=True)


class ActivityFeedItem(BaseModel):
    """Activity feed item"""
    id: UUID
    user_id: UUID
    username: str
    display_name: Optional[str] = None
    avatar_url: Optional[str] = None
    activity_type: str
    message: str
    activity_data: Optional[Dict[str, Any]] = None
    created_at: datetime
    
    model_config = ConfigDict(from_attributes=True)


class ActivityFeedResponse(BaseModel):
    """Activity feed"""
    activities: List[ActivityFeedItem]
    total: int
    has_more: bool = False
    
    model_config = ConfigDict(from_attributes=True)
