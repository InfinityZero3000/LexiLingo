"""
Gamification CRUD Operations
Phase 4: Database operations for Achievements, Leaderboards, Shop, and Social Features
"""

from typing import List, Optional, Tuple
from datetime import datetime, timedelta
from uuid import UUID
from sqlalchemy import select, func, and_, or_, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import (
    Achievement, UserAchievement, UserWallet, WalletTransaction,
    LeaderboardEntry, UserFollowing, ActivityFeed, ShopItem, UserInventory
)
from app.models.user import User


# ============================================================================
# Achievement CRUD
# ============================================================================

class AchievementCRUD:
    """CRUD operations for Achievements"""
    
    @staticmethod
    async def get_all_achievements(db: AsyncSession) -> List[Achievement]:
        """Get all achievement definitions"""
        result = await db.execute(
            select(Achievement).order_by(Achievement.category, Achievement.name)
        )
        return list(result.scalars().all())
    
    @staticmethod
    async def get_achievement(db: AsyncSession, achievement_id: UUID) -> Optional[Achievement]:
        """Get single achievement by ID"""
        result = await db.execute(
            select(Achievement).where(Achievement.id == achievement_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_user_achievements(db: AsyncSession, user_id: UUID) -> List[UserAchievement]:
        """Get all achievements unlocked by user"""
        result = await db.execute(
            select(UserAchievement)
            .where(UserAchievement.user_id == user_id)
            .order_by(desc(UserAchievement.unlocked_at))
        )
        return list(result.scalars().all())
    
    @staticmethod
    async def unlock_achievement(
        db: AsyncSession,
        user_id: UUID,
        achievement_id: UUID
    ) -> Optional[UserAchievement]:
        """Unlock an achievement for user (idempotent)"""
        # Check if already unlocked
        existing = await db.execute(
            select(UserAchievement).where(
                and_(
                    UserAchievement.user_id == user_id,
                    UserAchievement.achievement_id == achievement_id
                )
            )
        )
        if existing.scalar_one_or_none():
            return None  # Already unlocked
        
        user_achievement = UserAchievement(
            user_id=user_id,
            achievement_id=achievement_id
        )
        db.add(user_achievement)
        await db.commit()
        await db.refresh(user_achievement)
        return user_achievement


# ============================================================================
# Wallet CRUD
# ============================================================================

class WalletCRUD:
    """CRUD operations for User Wallet"""
    
    @staticmethod
    async def get_or_create_wallet(db: AsyncSession, user_id: UUID) -> UserWallet:
        """Get user's wallet, create if not exists"""
        result = await db.execute(
            select(UserWallet).where(UserWallet.user_id == user_id)
        )
        wallet = result.scalar_one_or_none()
        
        if not wallet:
            wallet = UserWallet(user_id=user_id, gems=0)
            db.add(wallet)
            await db.commit()
            await db.refresh(wallet)
        
        return wallet
    
    @staticmethod
    async def add_gems(
        db: AsyncSession,
        user_id: UUID,
        amount: int,
        source: str,
        description: str = None
    ) -> Tuple[UserWallet, WalletTransaction]:
        """Add gems to user's wallet"""
        wallet = await WalletCRUD.get_or_create_wallet(db, user_id)
        
        wallet.gems += amount
        wallet.total_gems_earned += amount
        
        transaction = WalletTransaction(
            wallet_id=wallet.id,
            user_id=user_id,
            transaction_type="earn",
            amount=amount,
            balance_after=wallet.gems,
            source=source,
            description=description
        )
        db.add(transaction)
        await db.commit()
        await db.refresh(wallet)
        
        return wallet, transaction
    
    @staticmethod
    async def spend_gems(
        db: AsyncSession,
        user_id: UUID,
        amount: int,
        source: str,
        reference_id: str = None,
        description: str = None
    ) -> Tuple[Optional[UserWallet], Optional[WalletTransaction]]:
        """Spend gems from wallet. Returns None if insufficient balance."""
        wallet = await WalletCRUD.get_or_create_wallet(db, user_id)
        
        if wallet.gems < amount:
            return None, None
        
        wallet.gems -= amount
        wallet.total_gems_spent += amount
        
        transaction = WalletTransaction(
            wallet_id=wallet.id,
            user_id=user_id,
            transaction_type="spend",
            amount=-amount,
            balance_after=wallet.gems,
            source=source,
            reference_id=reference_id,
            description=description
        )
        db.add(transaction)
        await db.commit()
        await db.refresh(wallet)
        
        return wallet, transaction
    
    @staticmethod
    async def get_transactions(
        db: AsyncSession,
        user_id: UUID,
        limit: int = 50
    ) -> List[WalletTransaction]:
        """Get user's transaction history"""
        result = await db.execute(
            select(WalletTransaction)
            .where(WalletTransaction.user_id == user_id)
            .order_by(desc(WalletTransaction.created_at))
            .limit(limit)
        )
        return list(result.scalars().all())


# ============================================================================
# Leaderboard CRUD
# ============================================================================

class LeaderboardCRUD:
    """CRUD operations for Leaderboards"""
    
    @staticmethod
    def get_current_week_range() -> Tuple[datetime, datetime]:
        """Get current week's start and end dates (Monday-Sunday)"""
        now = datetime.utcnow()
        week_start = now - timedelta(days=now.weekday())
        week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
        week_end = week_start + timedelta(days=7)
        return week_start, week_end
    
    @staticmethod
    async def get_or_create_entry(
        db: AsyncSession,
        user_id: UUID,
        league: str = "bronze"
    ) -> LeaderboardEntry:
        """Get or create leaderboard entry for current week"""
        week_start, week_end = LeaderboardCRUD.get_current_week_range()
        
        result = await db.execute(
            select(LeaderboardEntry).where(
                and_(
                    LeaderboardEntry.user_id == user_id,
                    LeaderboardEntry.week_start == week_start
                )
            )
        )
        entry = result.scalar_one_or_none()
        
        if not entry:
            entry = LeaderboardEntry(
                user_id=user_id,
                week_start=week_start,
                week_end=week_end,
                league=league
            )
            db.add(entry)
            await db.commit()
            await db.refresh(entry)
        
        return entry
    
    @staticmethod
    async def add_xp(
        db: AsyncSession,
        user_id: UUID,
        xp: int,
        lessons: int = 0
    ) -> LeaderboardEntry:
        """Add XP and lessons to user's leaderboard entry"""
        entry = await LeaderboardCRUD.get_or_create_entry(db, user_id)
        entry.xp_earned += xp
        entry.lessons_completed += lessons
        await db.commit()
        await db.refresh(entry)
        return entry
    
    @staticmethod
    async def get_leaderboard(
        db: AsyncSession,
        league: str,
        limit: int = 30
    ) -> List[Tuple[LeaderboardEntry, User]]:
        """Get leaderboard for specific league"""
        week_start, _ = LeaderboardCRUD.get_current_week_range()
        
        result = await db.execute(
            select(LeaderboardEntry, User)
            .join(User, User.id == LeaderboardEntry.user_id)
            .where(
                and_(
                    LeaderboardEntry.week_start == week_start,
                    LeaderboardEntry.league == league
                )
            )
            .order_by(desc(LeaderboardEntry.xp_earned))
            .limit(limit)
        )
        return list(result.all())
    
    @staticmethod
    async def get_user_rank(
        db: AsyncSession,
        user_id: UUID
    ) -> Optional[int]:
        """Get user's current rank in their league"""
        entry = await LeaderboardCRUD.get_or_create_entry(db, user_id)
        week_start, _ = LeaderboardCRUD.get_current_week_range()
        
        result = await db.execute(
            select(func.count())
            .where(
                and_(
                    LeaderboardEntry.week_start == week_start,
                    LeaderboardEntry.league == entry.league,
                    LeaderboardEntry.xp_earned > entry.xp_earned
                )
            )
        )
        rank = result.scalar() + 1
        return rank


# ============================================================================
# Shop CRUD
# ============================================================================

class ShopCRUD:
    """CRUD operations for Shop"""
    
    @staticmethod
    async def get_available_items(db: AsyncSession) -> List[ShopItem]:
        """Get all available shop items"""
        result = await db.execute(
            select(ShopItem)
            .where(ShopItem.is_available == True)
            .order_by(ShopItem.price_gems)
        )
        return list(result.scalars().all())
    
    @staticmethod
    async def get_item(db: AsyncSession, item_id: UUID) -> Optional[ShopItem]:
        """Get shop item by ID"""
        result = await db.execute(
            select(ShopItem).where(ShopItem.id == item_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def purchase_item(
        db: AsyncSession,
        user_id: UUID,
        item_id: UUID,
        quantity: int = 1
    ) -> Tuple[Optional[UserInventory], str]:
        """Purchase item from shop. Returns (inventory, message)"""
        item = await ShopCRUD.get_item(db, item_id)
        if not item:
            return None, "Item not found"
        
        if not item.is_available:
            return None, "Item is not available"
        
        if item.stock_quantity is not None and item.stock_quantity < quantity:
            return None, "Insufficient stock"
        
        total_cost = item.price_gems * quantity
        
        # Spend gems
        wallet, transaction = await WalletCRUD.spend_gems(
            db, user_id, total_cost,
            source="shop_purchase",
            reference_id=str(item_id),
            description=f"Purchased {quantity}x {item.name}"
        )
        
        if not wallet:
            return None, "Insufficient gems"
        
        # Update stock
        if item.stock_quantity is not None:
            item.stock_quantity -= quantity
        
        # Add to inventory (or update existing)
        result = await db.execute(
            select(UserInventory).where(
                and_(
                    UserInventory.user_id == user_id,
                    UserInventory.shop_item_id == item_id
                )
            )
        )
        inventory = result.scalar_one_or_none()
        
        if inventory:
            inventory.quantity += quantity
        else:
            inventory = UserInventory(
                user_id=user_id,
                shop_item_id=item_id,
                quantity=quantity
            )
            db.add(inventory)
        
        await db.commit()
        await db.refresh(inventory)
        
        return inventory, "Purchase successful"
    
    @staticmethod
    async def get_user_inventory(db: AsyncSession, user_id: UUID) -> List[UserInventory]:
        """Get user's inventory"""
        result = await db.execute(
            select(UserInventory)
            .where(UserInventory.user_id == user_id)
            .order_by(desc(UserInventory.purchased_at))
        )
        return list(result.scalars().all())


# ============================================================================
# Social CRUD
# ============================================================================

class SocialCRUD:
    """CRUD operations for Social features"""
    
    @staticmethod
    async def follow_user(
        db: AsyncSession,
        follower_id: UUID,
        following_id: UUID
    ) -> Tuple[bool, str]:
        """Follow a user. Returns (success, message)"""
        if follower_id == following_id:
            return False, "Cannot follow yourself"
        
        # Check if already following
        result = await db.execute(
            select(UserFollowing).where(
                and_(
                    UserFollowing.follower_id == follower_id,
                    UserFollowing.following_id == following_id
                )
            )
        )
        if result.scalar_one_or_none():
            return False, "Already following this user"
        
        following = UserFollowing(
            follower_id=follower_id,
            following_id=following_id
        )
        db.add(following)
        await db.commit()
        
        return True, "Now following user"
    
    @staticmethod
    async def unfollow_user(
        db: AsyncSession,
        follower_id: UUID,
        following_id: UUID
    ) -> Tuple[bool, str]:
        """Unfollow a user"""
        result = await db.execute(
            select(UserFollowing).where(
                and_(
                    UserFollowing.follower_id == follower_id,
                    UserFollowing.following_id == following_id
                )
            )
        )
        following = result.scalar_one_or_none()
        
        if not following:
            return False, "Not following this user"
        
        await db.delete(following)
        await db.commit()
        
        return True, "Unfollowed user"
    
    @staticmethod
    async def is_following(
        db: AsyncSession,
        follower_id: UUID,
        following_id: UUID
    ) -> bool:
        """Check if user is following another user"""
        result = await db.execute(
            select(UserFollowing).where(
                and_(
                    UserFollowing.follower_id == follower_id,
                    UserFollowing.following_id == following_id
                )
            )
        )
        return result.scalar_one_or_none() is not None
    
    @staticmethod
    async def get_followers(
        db: AsyncSession,
        user_id: UUID,
        limit: int = 50,
        offset: int = 0
    ) -> Tuple[List[User], int]:
        """Get user's followers"""
        # Count
        count_result = await db.execute(
            select(func.count())
            .where(UserFollowing.following_id == user_id)
        )
        total = count_result.scalar()
        
        # Get followers
        result = await db.execute(
            select(User)
            .join(UserFollowing, UserFollowing.follower_id == User.id)
            .where(UserFollowing.following_id == user_id)
            .offset(offset)
            .limit(limit)
        )
        return list(result.scalars().all()), total
    
    @staticmethod
    async def get_following(
        db: AsyncSession,
        user_id: UUID,
        limit: int = 50,
        offset: int = 0
    ) -> Tuple[List[User], int]:
        """Get users that user is following"""
        # Count
        count_result = await db.execute(
            select(func.count())
            .where(UserFollowing.follower_id == user_id)
        )
        total = count_result.scalar()
        
        # Get following
        result = await db.execute(
            select(User)
            .join(UserFollowing, UserFollowing.following_id == User.id)
            .where(UserFollowing.follower_id == user_id)
            .offset(offset)
            .limit(limit)
        )
        return list(result.scalars().all()), total
    
    @staticmethod
    async def create_activity(
        db: AsyncSession,
        user_id: UUID,
        activity_type: str,
        message: str,
        activity_data: dict = None,
        is_public: bool = True
    ) -> ActivityFeed:
        """Create activity feed entry"""
        activity = ActivityFeed(
            user_id=user_id,
            activity_type=activity_type,
            message=message,
            activity_data=activity_data,
            is_public=is_public
        )
        db.add(activity)
        await db.commit()
        await db.refresh(activity)
        return activity
    
    @staticmethod
    async def get_activity_feed(
        db: AsyncSession,
        user_id: UUID,
        limit: int = 20,
        offset: int = 0,
        include_own: bool = True
    ) -> List[Tuple[ActivityFeed, User]]:
        """Get activity feed for user (own + following)"""
        # Get following IDs
        following_result = await db.execute(
            select(UserFollowing.following_id)
            .where(UserFollowing.follower_id == user_id)
        )
        following_ids = [row[0] for row in following_result.all()]
        
        if include_own:
            following_ids.append(user_id)
        
        if not following_ids:
            return []
        
        result = await db.execute(
            select(ActivityFeed, User)
            .join(User, User.id == ActivityFeed.user_id)
            .where(
                and_(
                    ActivityFeed.user_id.in_(following_ids),
                    ActivityFeed.is_public == True
                )
            )
            .order_by(desc(ActivityFeed.created_at))
            .offset(offset)
            .limit(limit)
        )
        return list(result.all())
