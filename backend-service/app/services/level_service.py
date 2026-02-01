"""
Level Service

Business logic for level calculation and XP management.
Implements the level tier system: A1 (Beginner) to C2 (Mastery).
"""

from typing import Optional, Tuple
from app.schemas.level import LevelTier, LevelStatus


# Level tier definitions matching Flutter app
LEVEL_TIERS = [
    LevelTier(
        code="A1",
        name="Beginner",
        min_xp=0,
        max_xp=999,
        color="#4CAF50",
        description="Starting your English journey"
    ),
    LevelTier(
        code="A2",
        name="Elementary",
        min_xp=1000,
        max_xp=2999,
        color="#8BC34A",
        description="Building basic communication skills"
    ),
    LevelTier(
        code="B1",
        name="Intermediate",
        min_xp=3000,
        max_xp=6999,
        color="#2196F3",
        description="Comfortable with everyday situations"
    ),
    LevelTier(
        code="B2",
        name="Upper Intermediate",
        min_xp=7000,
        max_xp=14999,
        color="#3F51B5",
        description="Effective communication in most contexts"
    ),
    LevelTier(
        code="C1",
        name="Advanced",
        min_xp=15000,
        max_xp=29999,
        color="#9C27B0",
        description="Fluent and precise expression"
    ),
    LevelTier(
        code="C2",
        name="Mastery",
        min_xp=30000,
        max_xp=None,  # No upper limit
        color="#FF9800",
        description="Near-native proficiency"
    )
]


class LevelService:
    """Service for level-related calculations."""
    
    @staticmethod
    def get_all_tiers() -> list[LevelTier]:
        """Get all level tier definitions."""
        return LEVEL_TIERS
    
    @staticmethod
    def get_tier_by_code(code: str) -> Optional[LevelTier]:
        """Get tier by code (e.g., 'A1')."""
        for tier in LEVEL_TIERS:
            if tier.code == code:
                return tier
        return None
    
    @staticmethod
    def calculate_level_status(total_xp: int) -> LevelStatus:
        """
        Calculate current level status from total XP.
        
        Args:
            total_xp: Total XP earned by user
            
        Returns:
            LevelStatus with current tier and progress information
        """
        # Find current tier
        current_tier = LEVEL_TIERS[0]  # Default to A1
        
        for tier in LEVEL_TIERS:
            if total_xp >= tier.min_xp:
                if tier.max_xp is None or total_xp <= tier.max_xp:
                    current_tier = tier
                    break
        
        # Calculate progress within current tier
        xp_in_current_tier = total_xp - current_tier.min_xp
        
        # Calculate XP to next tier
        if current_tier.max_xp is None:
            # Max level reached
            xp_to_next_tier = None
            progress_percentage = 100.0
        else:
            tier_range = current_tier.max_xp - current_tier.min_xp + 1
            xp_to_next_tier = current_tier.max_xp - total_xp + 1
            progress_percentage = (xp_in_current_tier / tier_range) * 100
            progress_percentage = min(100.0, max(0.0, progress_percentage))
        
        return LevelStatus(
            current_tier=current_tier,
            total_xp=total_xp,
            xp_in_current_tier=xp_in_current_tier,
            xp_to_next_tier=xp_to_next_tier,
            progress_percentage=round(progress_percentage, 2)
        )
    
    @staticmethod
    def check_level_up(old_xp: int, new_xp: int) -> Tuple[bool, Optional[str]]:
        """
        Check if user leveled up.
        
        Args:
            old_xp: Previous total XP
            new_xp: New total XP
            
        Returns:
            Tuple of (leveled_up: bool, previous_tier_code: Optional[str])
        """
        old_status = LevelService.calculate_level_status(old_xp)
        new_status = LevelService.calculate_level_status(new_xp)
        
        if old_status.current_tier.code != new_status.current_tier.code:
            return True, old_status.current_tier.code
        
        return False, None
    
    @staticmethod
    def get_xp_for_tier(tier_code: str) -> Optional[int]:
        """Get minimum XP required for a specific tier."""
        tier = LevelService.get_tier_by_code(tier_code)
        if tier:
            return tier.min_xp
        return None
