"""
Gamification Models: Achievements, Leaderboards, and Virtual Economy
Phase 4: Integrated Gamification & Social Features
"""

import uuid
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, Text, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, GUIDArray


class Achievement(Base):
    """
    Achievement definitions.
    Phase 4: Badge system for user engagement.
    """
    
    __tablename__ = "achievements"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Achievement criteria
    condition_type: Mapped[str] = mapped_column(String(50), nullable=False)  # reach_streak_10, pass_level_a1, etc.
    condition_value: Mapped[int] = mapped_column(Integer, nullable=True)  # Threshold value
    condition_data: Mapped[dict] = mapped_column(JSON, nullable=True)  # Additional condition parameters
    
    # Display
    badge_icon: Mapped[str] = mapped_column(String(500), nullable=True)  # URL or icon name
    badge_color: Mapped[str] = mapped_column(String(20), nullable=True)  # Hex color
    category: Mapped[str] = mapped_column(String(50), nullable=True)  # streak, lessons, social, etc.
    
    # Rewards
    xp_reward: Mapped[int] = mapped_column(Integer, default=0)
    gems_reward: Mapped[int] = mapped_column(Integer, default=0)
    
    # Metadata
    rarity: Mapped[str] = mapped_column(String(20), default="common")  # common, rare, epic, legendary
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False)  # Hidden until unlocked
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<Achievement {self.name}>"


class UserAchievement(Base):
    """
    User-unlocked achievements.
    Phase 4: Track which badges users have earned.
    """
    
    __tablename__ = "user_achievements"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    achievement_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("achievements.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    unlocked_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    progress: Mapped[int] = mapped_column(Integer, default=0)  # For progressive achievements
    is_showcased: Mapped[bool] = mapped_column(Boolean, default=False)  # Display on profile
    
    def __repr__(self) -> str:
        return f"<UserAchievement user={self.user_id} achievement={self.achievement_id}>"


class UserWallet(Base):
    """
    Virtual currency wallet for users.
    Phase 4: Gems (in-app currency) management.
    """
    
    __tablename__ = "user_wallets"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True
    )
    
    gems: Mapped[int] = mapped_column(Integer, default=0)  # Virtual currency
    total_gems_earned: Mapped[int] = mapped_column(Integer, default=0)
    total_gems_spent: Mapped[int] = mapped_column(Integer, default=0)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    def __repr__(self) -> str:
        return f"<UserWallet user={self.user_id} gems={self.gems}>"


class WalletTransaction(Base):
    """
    Wallet transaction history.
    Phase 4: Audit trail for gem transactions.
    """
    
    __tablename__ = "wallet_transactions"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    wallet_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("user_wallets.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    transaction_type: Mapped[str] = mapped_column(String(50), nullable=False)  # earn, spend, purchase, reward
    amount: Mapped[int] = mapped_column(Integer, nullable=False)  # Positive for earn, negative for spend
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    
    # Transaction details
    source: Mapped[str] = mapped_column(String(100), nullable=True)  # lesson_complete, achievement, shop_purchase
    reference_id: Mapped[str] = mapped_column(String(255), nullable=True)  # ID of related entity
    description: Mapped[str] = mapped_column(Text, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    
    def __repr__(self) -> str:
        return f"<WalletTransaction {self.transaction_type} {self.amount}>"


class LeaderboardEntry(Base):
    """
    Weekly leaderboard entries.
    Phase 4: League-based competition system.
    """
    
    __tablename__ = "leaderboard_entries"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    # Weekly competition
    week_start: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    week_end: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    
    # League system
    league: Mapped[str] = mapped_column(String(20), default="bronze")  # bronze, silver, gold, platinum, diamond
    
    # Stats
    xp_earned: Mapped[int] = mapped_column(Integer, default=0)
    lessons_completed: Mapped[int] = mapped_column(Integer, default=0)
    current_rank: Mapped[int] = mapped_column(Integer, nullable=True)
    
    # Promotion/Demotion
    is_promoted: Mapped[bool] = mapped_column(Boolean, default=False)
    is_demoted: Mapped[bool] = mapped_column(Boolean, default=False)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow
    )
    
    def __repr__(self) -> str:
        return f"<LeaderboardEntry user={self.user_id} league={self.league} rank={self.current_rank}>"


class UserFollowing(Base):
    """
    Social following relationships.
    Phase 4: Friend/Following system for social features.
    """
    
    __tablename__ = "user_following"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    follower_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    following_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<UserFollowing {self.follower_id} -> {self.following_id}>"


class ActivityFeed(Base):
    """
    Social activity feed.
    Phase 4: Newsfeed showing friend activities.
    """
    
    __tablename__ = "activity_feeds"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    activity_type: Mapped[str] = mapped_column(String(50), nullable=False)  # lesson_complete, achievement_unlock, streak_milestone
    
    # Activity data (flexible JSON)
    activity_data: Mapped[dict] = mapped_column(JSON, nullable=True)
    
    # Display text (pre-generated for performance)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Visibility
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    
    def __repr__(self) -> str:
        return f"<ActivityFeed {self.activity_type} by {self.user_id}>"


class ShopItem(Base):
    """
    Virtual shop items.
    Phase 4: Items users can purchase with gems.
    """
    
    __tablename__ = "shop_items"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    
    item_type: Mapped[str] = mapped_column(String(50), nullable=False)  # streak_freeze, double_xp, hint_pack
    price_gems: Mapped[int] = mapped_column(Integer, nullable=False)
    
    # Item effects (JSON)
    effects: Mapped[dict] = mapped_column(JSON, nullable=True)  # {"duration_hours": 24, "multiplier": 2}
    
    # Display
    icon_url: Mapped[str] = mapped_column(String(500), nullable=True)
    
    # Inventory
    is_available: Mapped[bool] = mapped_column(Boolean, default=True)
    stock_quantity: Mapped[int] = mapped_column(Integer, nullable=True)  # Null = unlimited
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<ShopItem {self.name} - {self.price_gems} gems>"


class UserInventory(Base):
    """
    User-owned shop items.
    Phase 4: Track purchased items and their usage.
    """
    
    __tablename__ = "user_inventory"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    shop_item_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("shop_items.id", ondelete="CASCADE"),
        nullable=False
    )
    
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    
    # Usage tracking
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)  # For time-based items
    activated_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    
    purchased_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    def __repr__(self) -> str:
        return f"<UserInventory user={self.user_id} item={self.shop_item_id} qty={self.quantity}>"


class ChallengeRewardClaim(Base):
    """
    Track daily challenge reward claims.
    Phase 4: Prevents duplicate claims and records reward history.
    """
    
    __tablename__ = "challenge_reward_claims"
    
    id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        primary_key=True,
        default=uuid.uuid4
    )
    
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    challenge_id: Mapped[str] = mapped_column(String(100), nullable=False)  # Challenge template ID
    claim_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)  # Date of claim (for daily reset)
    
    xp_reward: Mapped[int] = mapped_column(Integer, default=0)
    gems_reward: Mapped[int] = mapped_column(Integer, default=0)
    
    claimed_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    
    __table_args__ = (
        Index('idx_challenge_claim_user_date', 'user_id', 'challenge_id', 'claim_date', unique=True),
    )
    
    def __repr__(self) -> str:
        return f"<ChallengeRewardClaim user={self.user_id} challenge={self.challenge_id}>"


# Create composite indexes for efficient queries
Index('idx_user_achievement_unique', UserAchievement.user_id, UserAchievement.achievement_id, unique=True)
Index('idx_leaderboard_week_league', LeaderboardEntry.week_start, LeaderboardEntry.league)
Index('idx_following_unique', UserFollowing.follower_id, UserFollowing.following_id, unique=True)
Index('idx_activity_feed_public', ActivityFeed.user_id, ActivityFeed.is_public, ActivityFeed.created_at)
