"""
Gamification Schemas
Phase 4: Schemas for Achievements, Leaderboards, Shop, and Social Features
"""

from datetime import datetime
from typing import Optional, List, Dict, Any
from uuid import UUID
from pydantic import BaseModel, Field
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
    DIAMOND = "diamond"


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
    
    class Config:
        from_attributes = True


class UserAchievementResponse(BaseModel):
    """User's unlocked achievement"""
    id: UUID
    achievement: AchievementResponse
    unlocked_at: datetime
    progress: int = 0
    is_showcased: bool = False
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


class WalletTransactionResponse(BaseModel):
    """Wallet transaction"""
    id: UUID
    transaction_type: str
    amount: int
    balance_after: int
    source: Optional[str] = None
    description: Optional[str] = None
    created_at: datetime
    
    class Config:
        from_attributes = True


class WalletHistoryResponse(BaseModel):
    """Wallet with transaction history"""
    wallet: WalletResponse
    transactions: List[WalletTransactionResponse]
    
    class Config:
        from_attributes = True


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
    xp_earned: int
    lessons_completed: int
    is_current_user: bool = False
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


class UserLeagueStatusResponse(BaseModel):
    """User's current league status"""
    league: str
    current_rank: Optional[int] = None
    xp_earned: int
    lessons_completed: int
    is_in_promotion_zone: bool = False
    is_in_demotion_zone: bool = False
    week_ends_in_hours: int
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


class UserInventoryItemResponse(BaseModel):
    """User's inventory item"""
    id: UUID
    item: ShopItemResponse
    quantity: int
    is_active: bool = False
    activated_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    purchased_at: datetime
    
    class Config:
        from_attributes = True


class InventoryResponse(BaseModel):
    """User's full inventory"""
    items: List[UserInventoryItemResponse]
    total_items: int
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


class FollowersListResponse(BaseModel):
    """List of followers/following"""
    users: List[UserSocialProfile]
    total: int
    
    class Config:
        from_attributes = True


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
    
    class Config:
        from_attributes = True


class ActivityFeedResponse(BaseModel):
    """Activity feed"""
    activities: List[ActivityFeedItem]
    total: int
    has_more: bool = False
    
    class Config:
        from_attributes = True
