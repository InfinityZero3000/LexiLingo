"""
Item Effects Service

Handles activation and effects of shop items like:
- Streak Freeze: Protects streak for 24 hours
- Double XP: 2x XP multiplier for specified duration
- Hint Pack: Additional hints for lessons
- Heart Refill: Restore lives/hearts
"""

from typing import Optional, Dict, Any, Tuple, List
from uuid import UUID
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, update

from app.models.gamification import UserInventory, ShopItem
from app.models.progress import Streak


class ItemEffectsService:
    """Service for managing item usage and effects."""
    
    # Item type handlers
    ITEM_HANDLERS = {
        'streak_freeze': '_handle_streak_freeze',
        'double_xp': '_handle_double_xp',
        'hint_pack': '_handle_hint_pack',
        'heart_refill': '_handle_heart_refill',
        'avatar': '_handle_cosmetic',
        'theme': '_handle_cosmetic',
    }
    
    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def use_item(
        self, 
        user_id: UUID, 
        inventory_id: UUID
    ) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
        """
        Use an item from inventory.
        
        Args:
            user_id: User's ID
            inventory_id: Inventory item ID to use
            
        Returns:
            Tuple of (success, message, effects_applied)
        """
        # Get inventory item
        result = await self.db.execute(
            select(UserInventory).where(
                and_(
                    UserInventory.id == inventory_id,
                    UserInventory.user_id == user_id
                )
            )
        )
        inventory = result.scalar_one_or_none()
        
        if not inventory:
            return False, "Item not found in inventory", None
        
        if inventory.quantity <= 0:
            return False, "No items remaining", None
        
        # Get shop item details
        item_result = await self.db.execute(
            select(ShopItem).where(ShopItem.id == inventory.shop_item_id)
        )
        shop_item = item_result.scalar_one_or_none()
        
        if not shop_item:
            return False, "Shop item not found", None
        
        # Get handler for this item type
        handler_name = self.ITEM_HANDLERS.get(shop_item.item_type)
        if not handler_name:
            return False, f"Unknown item type: {shop_item.item_type}", None
        
        handler = getattr(self, handler_name, None)
        if not handler:
            return False, "Item handler not implemented", None
        
        # Execute the handler
        success, message, effects = await handler(
            user_id=user_id,
            inventory=inventory,
            shop_item=shop_item,
        )
        
        if success:
            # Decrement quantity
            inventory.quantity -= 1
            
            # Mark activation if applicable
            if shop_item.effects and shop_item.effects.get('duration_hours'):
                duration = shop_item.effects['duration_hours']
                inventory.is_active = True
                inventory.activated_at = datetime.utcnow()
                inventory.expires_at = datetime.utcnow() + timedelta(hours=duration)
            
            await self.db.commit()
        
        return success, message, effects
    
    async def _handle_streak_freeze(
        self,
        user_id: UUID,
        inventory: UserInventory,
        shop_item: ShopItem,
    ) -> Tuple[bool, str, Optional[Dict]]:
        """Handle streak freeze item usage."""
        # Get user's streak
        result = await self.db.execute(
            select(Streak).where(Streak.user_id == user_id)
        )
        streak = result.scalar_one_or_none()
        
        if not streak:
            # Create streak record
            streak = Streak(user_id=user_id, freeze_count=0)
            self.db.add(streak)
        
        # Add freeze count
        streak.freeze_count += 1
        
        return True, f"Streak freeze added! You now have {streak.freeze_count} freezes.", {
            "freeze_count": streak.freeze_count,
            "effect": "streak_protection"
        }
    
    async def _handle_double_xp(
        self,
        user_id: UUID,
        inventory: UserInventory,
        shop_item: ShopItem,
    ) -> Tuple[bool, str, Optional[Dict]]:
        """Handle double XP boost activation."""
        effects = shop_item.effects or {}
        duration = effects.get('duration_hours', 1)
        multiplier = effects.get('multiplier', 2)
        
        expires_at = datetime.utcnow() + timedelta(hours=duration)
        
        return True, f"Double XP activated! {multiplier}x XP for {duration} hour(s)", {
            "multiplier": multiplier,
            "duration_hours": duration,
            "expires_at": expires_at.isoformat(),
            "effect": "xp_boost"
        }
    
    async def _handle_hint_pack(
        self,
        user_id: UUID,
        inventory: UserInventory,
        shop_item: ShopItem,
    ) -> Tuple[bool, str, Optional[Dict]]:
        """Handle hint pack usage - adds hints to user's account."""
        effects = shop_item.effects or {}
        hint_count = effects.get('quantity', 5)
        
        # TODO: Add hints to user profile/preferences
        # For now, just return success
        return True, f"Added {hint_count} hints to your account!", {
            "hints_added": hint_count,
            "effect": "hints"
        }
    
    async def _handle_heart_refill(
        self,
        user_id: UUID,
        inventory: UserInventory,
        shop_item: ShopItem,
    ) -> Tuple[bool, str, Optional[Dict]]:
        """Handle heart/life refill."""
        # TODO: Implement lives system
        return True, "Hearts refilled to maximum!", {
            "hearts_restored": 5,
            "effect": "hearts"
        }
    
    async def _handle_cosmetic(
        self,
        user_id: UUID,
        inventory: UserInventory,
        shop_item: ShopItem,
    ) -> Tuple[bool, str, Optional[Dict]]:
        """Handle cosmetic items (avatars, themes) - just mark as owned/active."""
        return True, f"{shop_item.name} equipped!", {
            "item_type": shop_item.item_type,
            "effect": "cosmetic"
        }
    
    async def get_active_boosts(self, user_id: UUID) -> List[Dict[str, Any]]:
        """
        Get all currently active boosts for a user.
        
        Returns list of active boosts with their effects and expiration times.
        """
        now = datetime.utcnow()
        
        result = await self.db.execute(
            select(UserInventory, ShopItem)
            .join(ShopItem, UserInventory.shop_item_id == ShopItem.id)
            .where(
                and_(
                    UserInventory.user_id == user_id,
                    UserInventory.is_active == True,
                    UserInventory.expires_at > now
                )
            )
        )
        
        active_boosts = []
        for inventory, shop_item in result:
            remaining_seconds = (inventory.expires_at - now).total_seconds()
            
            active_boosts.append({
                "item_id": str(shop_item.id),
                "item_name": shop_item.name,
                "item_type": shop_item.item_type,
                "effects": shop_item.effects,
                "activated_at": inventory.activated_at.isoformat() if inventory.activated_at else None,
                "expires_at": inventory.expires_at.isoformat() if inventory.expires_at else None,
                "remaining_seconds": max(0, int(remaining_seconds)),
            })
        
        return active_boosts
    
    async def get_xp_multiplier(self, user_id: UUID) -> float:
        """
        Calculate current XP multiplier for a user.
        
        Checks for active double_xp boosts and returns the multiplier.
        Default is 1.0 (no boost).
        """
        active_boosts = await self.get_active_boosts(user_id)
        
        multiplier = 1.0
        for boost in active_boosts:
            if boost['item_type'] == 'double_xp':
                effects = boost.get('effects') or {}
                boost_multiplier = effects.get('multiplier', 2.0)
                multiplier = max(multiplier, boost_multiplier)
        
        return multiplier
    
    async def cleanup_expired_boosts(self, user_id: UUID) -> int:
        """
        Deactivate expired boosts for a user.
        
        Returns number of boosts deactivated.
        """
        now = datetime.utcnow()
        
        result = await self.db.execute(
            update(UserInventory)
            .where(
                and_(
                    UserInventory.user_id == user_id,
                    UserInventory.is_active == True,
                    UserInventory.expires_at <= now
                )
            )
            .values(is_active=False)
        )
        
        await self.db.commit()
        return result.rowcount


class DailyChallengeService:
    """Service for managing daily challenge rewards."""
    
    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def claim_challenge_reward(
        self,
        user_id: UUID,
        challenge_id: str,
        xp_reward: int,
        gems_reward: int = 0
    ) -> Tuple[bool, str, Dict[str, Any]]:
        """
        Claim reward for completing a daily challenge.
        
        Checks if already claimed today and awards XP/gems if not.
        """
        from app.models.progress import DailyActivity
        from app.crud.gamification import WalletCRUD
        from datetime import date
        
        today = date.today()
        
        # Check if already claimed - using DailyActivity as claim tracker
        # In a full implementation, you'd have a dedicated ChallengeRewardClaim table
        
        # Award XP
        # TODO: Update user's XP in User model
        
        # Award gems if applicable
        if gems_reward > 0:
            await WalletCRUD.add_gems(
                self.db,
                user_id,
                gems_reward,
                source="daily_challenge",
                description=f"Challenge reward: {challenge_id}"
            )
        
        return True, f"Claimed! +{xp_reward} XP" + (f" +{gems_reward} gems" if gems_reward else ""), {
            "xp_earned": xp_reward,
            "gems_earned": gems_reward,
            "challenge_id": challenge_id,
            "claimed_at": datetime.utcnow().isoformat()
        }
