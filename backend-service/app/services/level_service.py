"""
Level Service

Business logic for level calculation and XP management.

Two systems:
1. Proficiency Tier system: A1-C2 (CEFR-based, for language proficiency)
2. Numeric Level system: 1, 2, 3... (XP-based, for gamification)

Numeric Level Formula: XP needed = floor(100 * (level ** 1.5))
"""

import math
from typing import Optional, Tuple
from dataclasses import dataclass
from app.schemas.level import LevelTier, LevelStatus


# ============================================================================
# Proficiency Tier System (CEFR: A1-C2) - Existing system
# ============================================================================

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
        max_xp=None,
        color="#FF9800",
        description="Near-native proficiency"
    )
]


# ============================================================================
# Numeric Level System (Gamification)
# ============================================================================

@dataclass
class NumericLevelInfo:
    """Numeric level information for gamification."""
    numeric_level: int
    current_xp_in_level: int
    xp_for_next_level: int
    level_progress_percent: float
    total_xp: int


def xp_for_single_level(level: int) -> int:
    """
    Calculate XP required to complete a single level.
    Formula: floor(100 * (level ** 1.5))
    
    Level 1:   100 XP
    Level 5:   1,118 XP
    Level 10:  3,162 XP
    Level 20:  8,944 XP
    Level 50:  35,355 XP
    Level 100: 100,000 XP
    """
    return int(math.floor(100 * (level ** 1.5)))


def total_xp_for_level(level: int) -> int:
    """Calculate total cumulative XP needed to reach a given level."""
    total = 0
    for lvl in range(1, level):
        total += xp_for_single_level(lvl)
    return total


def calculate_numeric_level(total_xp: int) -> int:
    """
    Calculate numeric level from total XP.
    Iterates through levels, subtracting required XP until exhausted.
    """
    if total_xp <= 0:
        return 1
    
    remaining_xp = total_xp
    level = 1
    
    while True:
        xp_needed = xp_for_single_level(level)
        if remaining_xp < xp_needed:
            break
        remaining_xp -= xp_needed
        level += 1
    
    return level


def get_numeric_level_progress(total_xp: int) -> NumericLevelInfo:
    """
    Get detailed numeric level progress information.
    
    Returns:
        NumericLevelInfo with current level, XP progress, percentage
    """
    level = calculate_numeric_level(total_xp)
    xp_spent = total_xp_for_level(level)
    current_xp_in_level = total_xp - xp_spent
    xp_needed = xp_for_single_level(level)
    progress = (current_xp_in_level / xp_needed * 100) if xp_needed > 0 else 100.0
    
    return NumericLevelInfo(
        numeric_level=level,
        current_xp_in_level=current_xp_in_level,
        xp_for_next_level=xp_needed,
        level_progress_percent=round(progress, 2),
        total_xp=total_xp,
    )


def check_numeric_level_up(old_xp: int, new_xp: int) -> Tuple[bool, int, int]:
    """
    Check if user's numeric level changed.
    
    Returns:
        (leveled_up, old_level, new_level)
    """
    old_level = calculate_numeric_level(old_xp)
    new_level = calculate_numeric_level(new_xp)
    return (new_level > old_level, old_level, new_level)


# ============================================================================
# LevelService class (backward compatible)
# ============================================================================

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
        Calculate current CEFR level status from total XP.
        """
        current_tier = LEVEL_TIERS[0]
        
        for tier in LEVEL_TIERS:
            if total_xp >= tier.min_xp:
                if tier.max_xp is None or total_xp <= tier.max_xp:
                    current_tier = tier
                    break
        
        xp_in_current_tier = total_xp - current_tier.min_xp
        
        if current_tier.max_xp is None:
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
        """Check if user's CEFR tier changed."""
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
