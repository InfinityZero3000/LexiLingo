"""
Gamification CRUD Operations
Phase 4: Database operations for Achievements, Leaderboards, Shop, and Social Features
"""

from typing import List, Optional, Tuple
from datetime import datetime, timedelta, timezone
from uuid import UUID
from sqlalchemy import select, func, and_, or_, desc
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import (
    Achievement, UserAchievement, UserWallet, WalletTransaction,
    LeaderboardEntry, UserFollowing, ActivityFeed, ShopItem, UserInventory
)
from app.models.user import User
from app.crud.leaderboard import competition_rank


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
    async def get_user_achievements(
        db: AsyncSession, 
        user_id: UUID,
        order_by_recent: bool = True,
        limit: Optional[int] = None
    ) -> List[UserAchievement]:
        """
        Get achievements unlocked by user.
        
        Args:
            db: Database session
            user_id: User's UUID
            order_by_recent: If True, order by most recently unlocked first
            limit: Maximum number of results to return (None = all)
            
        Returns:
            List of UserAchievement records
        """
        query = select(UserAchievement).where(UserAchievement.user_id == user_id)
        
        if order_by_recent:
            query = query.order_by(desc(UserAchievement.unlocked_at))
        
        if limit:
            query = query.limit(limit)
            
        result = await db.execute(query)
        return list(result.scalars().all())
    
    @staticmethod
    async def get_user_achievements_with_details(
        db: AsyncSession,
        user_id: UUID,
        order_by_recent: bool = True,
        limit: Optional[int] = None
    ) -> List[tuple]:
        """
        Get user achievements with achievement details in a single JOIN query.
        Returns list of (UserAchievement, Achievement) tuples.
        """
        query = (
            select(UserAchievement, Achievement)
            .join(Achievement, Achievement.id == UserAchievement.achievement_id)
            .where(UserAchievement.user_id == user_id)
        )
        if order_by_recent:
            query = query.order_by(desc(UserAchievement.unlocked_at))
        if limit:
            query = query.limit(limit)
        result = await db.execute(query)
        return list(result.all())

    @staticmethod
    async def unlock_achievement(
        db: AsyncSession,
        user_id: UUID,
        achievement_id: UUID
    ) -> Optional[UserAchievement]:
        """Unlock an achievement for user (idempotent, race-safe)"""
        user_achievement = UserAchievement(
            user_id=user_id,
            achievement_id=achievement_id
        )
        db.add(user_achievement)
        try:
            await db.commit()
            await db.refresh(user_achievement)
            return user_achievement
        except IntegrityError:
            await db.rollback()
            return None  # Already unlocked


# ============================================================================
# Wallet CRUD
# ============================================================================

class WalletCRUD:
    """CRUD operations for User Wallet"""
    
    @staticmethod
    async def get_or_create_wallet(db: AsyncSession, user_id: UUID) -> UserWallet:
        """Get user's wallet, create if not exists (handles race condition)."""
        result = await db.execute(
            select(UserWallet).where(UserWallet.user_id == user_id)
        )
        wallet = result.scalar_one_or_none()
        
        if not wallet:
            try:
                wallet = UserWallet(user_id=user_id, gems=0)
                db.add(wallet)
                await db.commit()
                await db.refresh(wallet)
            except Exception:
                await db.rollback()
                # Another request created it concurrently — re-fetch
                result = await db.execute(
                    select(UserWallet).where(UserWallet.user_id == user_id)
                )
                wallet = result.scalar_one_or_none()
                if not wallet:
                    raise
        
        return wallet
    
    @staticmethod
    async def add_gems(
        db: AsyncSession,
        user_id: UUID,
        amount: int,
        source: str,
        description: str = None,
        commit: bool = True,
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
        if commit:
            await db.commit()
            await db.refresh(wallet)
        else:
            await db.flush()
        
        return wallet, transaction
    
    @staticmethod
    async def spend_gems(
        db: AsyncSession,
        user_id: UUID,
        amount: int,
        source: str,
        reference_id: str = None,
        description: str = None,
        commit: bool = True,
    ) -> Tuple[Optional[UserWallet], Optional[WalletTransaction]]:
        """Spend gems from wallet. Returns None if insufficient balance.
        Uses SELECT FOR UPDATE to prevent double-spending race conditions."""
        # Lock the wallet row to prevent concurrent spending
        result = await db.execute(
            select(UserWallet)
            .where(UserWallet.user_id == user_id)
            .with_for_update()
        )
        wallet = result.scalar_one_or_none()
        if not wallet:
            wallet = UserWallet(user_id=user_id, gems=0)
            db.add(wallet)
            await db.flush()
        
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
        if commit:
            await db.commit()
            await db.refresh(wallet)
        else:
            await db.flush()
        
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
        now = datetime.now(timezone.utc)
        week_start = now - timedelta(days=now.weekday())
        week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
        week_end = week_start + timedelta(days=7)
        return week_start, week_end
    
    @staticmethod
    async def get_or_create_entry(
        db: AsyncSession,
        user_id: UUID,
        league: Optional[str] = None,
    ) -> LeaderboardEntry:
        """Get or create leaderboard entry for current week"""
        week_start, week_end = LeaderboardCRUD.get_current_week_range()
        user_result = await db.execute(select(User).where(User.id == user_id))
        user = user_result.scalar_one_or_none()
        resolved_league = (
            (getattr(user, "rank", None) or league or "bronze")
            .lower()
            .strip()
        )
        
        result = await db.execute(
            select(LeaderboardEntry).where(
                and_(
                    LeaderboardEntry.user_id == user_id,
                    LeaderboardEntry.week_start == week_start
                )
            )
        )
        entry = result.scalar_one_or_none()

        if entry and entry.league != resolved_league:
            entry.league = resolved_league
            await db.commit()
            await db.refresh(entry)
        
        if not entry:
            entry = LeaderboardEntry(
                user_id=user_id,
                week_start=week_start,
                week_end=week_end,
                league=resolved_league,
            )
            db.add(entry)
            try:
                await db.commit()
                await db.refresh(entry)
            except IntegrityError:
                await db.rollback()
                result = await db.execute(
                    select(LeaderboardEntry).where(
                        and_(
                            LeaderboardEntry.user_id == user_id,
                            LeaderboardEntry.week_start == week_start,
                        )
                    )
                )
                entry = result.scalar_one_or_none()
                if not entry:
                    raise
        
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
    ) -> List[Tuple[Optional[LeaderboardEntry], User]]:
        """Get leaderboard for specific league"""
        week_start, _ = LeaderboardCRUD.get_current_week_range()
        league_filter = league.lower().strip()
        
        result = await db.execute(
            select(LeaderboardEntry, User)
            .select_from(User)
            .outerjoin(
                LeaderboardEntry, 
                and_(
                    LeaderboardEntry.user_id == User.id,
                    LeaderboardEntry.week_start == week_start,
                )
            )
            .where(
                and_(
                    User.is_active == True,
                    func.lower(User.rank) == league_filter,
                )
            )
            .order_by(
                desc(func.coalesce(LeaderboardEntry.xp_earned, 0)),
                desc(User.total_xp),
                desc(User.updated_at)
            )
            .limit(limit)
        )
        return list(result.all())

    @staticmethod
    async def sync_current_week_entries_to_user_rank(db: AsyncSession) -> None:
        """Keep each weekly leaderboard entry aligned to the user's single rank."""
        week_start, _ = LeaderboardCRUD.get_current_week_range()
        result = await db.execute(
            select(LeaderboardEntry, User.rank)
            .join(User, User.id == LeaderboardEntry.user_id)
            .where(LeaderboardEntry.week_start == week_start)
        )

        changed = False
        for entry, user_rank in result.all():
            resolved_rank = (user_rank or "bronze").lower().strip()
            if entry.league != resolved_rank:
                entry.league = resolved_rank
                changed = True

        if changed:
            await db.commit()

    @staticmethod
    async def get_leaderboard_from_users(
        db: AsyncSession,
        league: str,
        limit: int = 30,
    ) -> Tuple[List[User], int]:
        """Return league users for a zero-XP weekly leaderboard."""
        league_filter = league.lower().strip()

        base_query = select(User).where(User.is_active == True)
        if league_filter:
            base_query = base_query.where(func.lower(User.rank) == league_filter)

        count_query = select(func.count()).select_from(base_query.subquery())
        total = int((await db.execute(count_query)).scalar() or 0)

        result = await db.execute(
            base_query
            .order_by(desc(User.updated_at), User.id)
            .limit(limit)
        )
        return list(result.scalars().all()), total

    @staticmethod
    async def count_rank_participants(db: AsyncSession, league: str) -> int:
        """Count active users whose single persisted rank matches the requested league."""
        league_filter = league.lower().strip()
        result = await db.execute(
            select(func.count()).select_from(User).where(
                and_(
                    User.is_active == True,
                    func.lower(User.rank) == league_filter,
                )
            )
        )
        return int(result.scalar() or 0)
    
    @staticmethod
    async def get_user_rank(
        db: AsyncSession,
        user_id: UUID
    ) -> Optional[int]:
        """Get user's current rank in their league"""
        entry = await LeaderboardCRUD.get_or_create_entry(db, user_id)
        week_start, _ = LeaderboardCRUD.get_current_week_range()
        user_result = await db.execute(select(User.rank).where(User.id == user_id))
        league = (user_result.scalar_one_or_none() or entry.league or "bronze").lower()
        
        result = await db.execute(
            select(func.count())
            .select_from(LeaderboardEntry)
            .join(User, User.id == LeaderboardEntry.user_id)
            .where(
                and_(
                    LeaderboardEntry.week_start == week_start,
                    func.lower(User.rank) == league,
                    LeaderboardEntry.xp_earned > entry.xp_earned
                )
            )
        )
        rank = result.scalar() + 1
        return rank

    @staticmethod
    def rank_scores(scores: List[int]) -> List[int]:
        """Expose the canonical competition ranking policy."""
        from app.crud.leaderboard import competition_ranks

        return competition_ranks(scores)

    @staticmethod
    def rank_for_score(score: int, scores: List[int]) -> int:
        """Return the canonical rank for a score among league scores."""
        return competition_rank(score, scores)


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

        if item.item_type == "avatar":
            if quantity != 1:
                return None, "Avatars can only be purchased once"
            owned_result = await db.execute(
                select(UserInventory).where(
                    and_(
                        UserInventory.user_id == user_id,
                        UserInventory.shop_item_id == item_id,
                    )
                )
            )
            if owned_result.scalar_one_or_none():
                return None, "Avatar already owned"
        
        total_cost = item.price_gems * quantity
        
        # Spend gems
        wallet, transaction = await WalletCRUD.spend_gems(
            db, user_id, total_cost,
            source="shop_purchase",
            reference_id=str(item_id),
            description=f"Purchased {quantity}x {item.name}",
            commit=False,
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
    
    @staticmethod
    async def get_user_inventory_with_items(db: AsyncSession, user_id: UUID) -> List[tuple]:
        """Get user's inventory with shop item details in a single JOIN query.
        Returns list of (UserInventory, ShopItem) tuples."""
        result = await db.execute(
            select(UserInventory, ShopItem)
            .join(ShopItem, ShopItem.id == UserInventory.shop_item_id)
            .where(UserInventory.user_id == user_id)
            .order_by(desc(UserInventory.purchased_at))
        )
        return list(result.all())


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
    async def get_following_ids(
        db: AsyncSession,
        follower_id: UUID,
        target_ids: List[UUID]
    ) -> set:
        """Batch check: return set of user_ids from target_ids that follower_id follows."""
        if not target_ids:
            return set()
        result = await db.execute(
            select(UserFollowing.following_id).where(
                and_(
                    UserFollowing.follower_id == follower_id,
                    UserFollowing.following_id.in_(target_ids)
                )
            )
        )
        return {row[0] for row in result.all()}
    
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

    @staticmethod
    async def get_friend_suggestions(
        db: AsyncSession,
        user_id: UUID,
        limit: int = 10,
        offset: int = 0,
    ) -> List[Tuple[User, float, int, List[str]]]:
        """Suggest users based on CEFR level, XP proximity, language, and mutual follows."""
        current_user_result = await db.execute(
            select(User).where(User.id == user_id)
        )
        current_user = current_user_result.scalar_one_or_none()
        if not current_user:
            return []

        following_result = await db.execute(
            select(UserFollowing.following_id).where(UserFollowing.follower_id == user_id)
        )
        following_ids = {row[0] for row in following_result.all()}

        candidate_limit = max((offset + limit) * 8, 80)
        candidates_query = (
            select(User)
            .where(
                and_(
                    User.is_active == True,
                    User.id != user_id,
                    User.id.notin_(list(following_ids)) if following_ids else True,
                )
            )
            .order_by(desc(User.updated_at))
            .limit(candidate_limit)
        )
        candidates = list((await db.execute(candidates_query)).scalars().all())
        if not candidates:
            return []

        candidate_ids = [candidate.id for candidate in candidates]
        mutual_counts: dict[UUID, int] = {}
        if following_ids:
            mutual_rows = await db.execute(
                select(
                    UserFollowing.following_id,
                    func.count(UserFollowing.follower_id),
                )
                .where(
                    and_(
                        UserFollowing.following_id.in_(candidate_ids),
                        UserFollowing.follower_id.in_(list(following_ids)),
                    )
                )
                .group_by(UserFollowing.following_id)
            )
            mutual_counts = {row[0]: int(row[1]) for row in mutual_rows.all()}

        now = datetime.now(timezone.utc)
        denominator = max(current_user.total_xp, 500)
        scored: List[Tuple[User, float, int, List[str]]] = []

        for candidate in candidates:
            reasons: List[str] = []

            level_score = 0.0
            if candidate.level == current_user.level:
                level_score = 1.0
                reasons.append("same_cefr")
            elif abs((candidate.numeric_level or 1) - (current_user.numeric_level or 1)) <= 1:
                level_score = 0.5

            xp_diff = abs((candidate.total_xp or 0) - (current_user.total_xp or 0))
            xp_score = max(0.0, 1.0 - min(1.0, xp_diff / denominator))
            if xp_score >= 0.7:
                reasons.append("similar_xp")

            language_score = 0.0
            if candidate.target_language == current_user.target_language:
                language_score = 1.0
                reasons.append("same_target_language")

            mutual_count = mutual_counts.get(candidate.id, 0)
            mutual_score = min(1.0, mutual_count / 5)
            if mutual_count > 0:
                reasons.append("mutual_connections")

            recency_score = 0.0
            if candidate.updated_at:
                hours = max((now - candidate.updated_at).total_seconds() / 3600.0, 0.0)
                recency_score = max(0.0, 1.0 - min(1.0, hours / (24 * 14)))

            final_score = (
                0.30 * level_score
                + 0.25 * xp_score
                + 0.20 * language_score
                + 0.15 * mutual_score
                + 0.10 * recency_score
            )

            scored.append((candidate, round(final_score, 4), mutual_count, reasons))

        scored.sort(key=lambda row: (-row[1], -(row[2]), -(row[0].total_xp or 0)))
        return scored[offset : offset + limit]
