"""
Rank Service

Calculates user rank based on weighted score of:
- Numeric Level (60% weight)
- Proficiency Level A1-C2 (40% weight)

Rank Tiers:
- Bronze: 0-39 points
- Silver: 40-54 points
- Gold: 55-69 points
- Platinum: 70-84 points
- Diamond: 85-94 points
- Master: 95+ points
"""

from dataclasses import dataclass
from typing import Optional, Tuple
from enum import Enum


class RankTier(str, Enum):
    """Rank tier enumeration."""
    BRONZE = "bronze"
    SILVER = "silver"
    GOLD = "gold"
    PLATINUM = "platinum"
    DIAMOND = "diamond"
    MASTER = "master"


@dataclass
class RankInfo:
    """Rank information."""
    rank: RankTier
    name: str
    score: float
    level_score: float
    proficiency_score: float
    color: str
    icon: str
    min_score: int
    max_score: Optional[int]


# Proficiency value mapping (A1 to C2)
PROFICIENCY_VALUES = {
    "A1": 10,
    "A2": 20,
    "B1": 30,
    "B2": 40,
    "C1": 50,
    "C2": 60,
}

# Rank tier definitions with thresholds (min_score inclusive, max_score exclusive except Master)
# Using only min_score for determination: score >= min_s picks the rank
RANK_THRESHOLDS = [
    (RankTier.BRONZE, "Bronze", 0, 40, "#CD7F32", "🥉"),
    (RankTier.SILVER, "Silver", 40, 55, "#C0C0C0", "🥈"),
    (RankTier.GOLD, "Gold", 55, 70, "#FFD700", "🥇"),
    (RankTier.PLATINUM, "Platinum", 70, 85, "#E5E4E2", "💎"),
    (RankTier.DIAMOND, "Diamond", 85, 95, "#B9F2FF", "💠"),
    (RankTier.MASTER, "Master", 95, 101, "#9966CC", "👑"),
]


def get_proficiency_value(proficiency_level: str) -> int:
    """
    Get numeric value for proficiency level.
    
    Args:
        proficiency_level: CEFR level code (A1-C2)
        
    Returns:
        Numeric value for ranking calculation
    """
    return PROFICIENCY_VALUES.get(proficiency_level.upper(), 10)


def calculate_rank_score(numeric_level: int, proficiency_level: str) -> float:
    """
    Calculate weighted rank score.
    
    Formula:
    - Level Score = min(numeric_level, 100) / 100 * 60 (max 60 points)
    - Proficiency Score = proficiency_value * 40 / 60 (max 40 points)
    - Total Score = Level Score + Proficiency Score (0-100 points)
    
    Args:
        numeric_level: User's numeric level (1, 2, 3, ...)
        proficiency_level: User's CEFR proficiency (A1-C2)
        
    Returns:
        Weighted score (0-100)
    """
    # Level contributes 60% of score (capped at level 100)
    capped_level = min(numeric_level, 100)
    level_score = (capped_level / 100) * 60
    
    # Proficiency contributes 40% of score
    prof_value = get_proficiency_value(proficiency_level)
    proficiency_score = (prof_value / 60) * 40
    
    total_score = level_score + proficiency_score
    
    return round(total_score, 2)


def calculate_rank(numeric_level: int, proficiency_level: str) -> RankInfo:
    """
    Calculate user's rank based on level and proficiency.
    
    Args:
        numeric_level: User's numeric level
        proficiency_level: User's CEFR proficiency (A1-C2)
        
    Returns:
        RankInfo with rank details
    """
    score = calculate_rank_score(numeric_level, proficiency_level)
    
    # Determine rank tier from score
    rank_tier = RankTier.BRONZE
    rank_name = "Bronze"
    min_score = 0
    max_score = 39
    color = "#CD7F32"
    icon = "🥉"
    
    for tier, name, min_s, max_s, c, i in RANK_THRESHOLDS:
        if min_s <= score < max_s:
            rank_tier = tier
            rank_name = name
            min_score = min_s
            max_score = max_s
            color = c
            icon = i
            break
        elif score >= 95:  # Master is special case
            rank_tier = RankTier.MASTER
            rank_name = "Master"
            min_score = 95
            max_score = 100
            color = "#9966CC"
            icon = "👑"
            break
    
    # Calculate component scores
    capped_level = min(numeric_level, 100)
    level_score = (capped_level / 100) * 60
    
    prof_value = get_proficiency_value(proficiency_level)
    proficiency_score = (prof_value / 60) * 40
    
    return RankInfo(
        rank=rank_tier,
        name=rank_name,
        score=score,
        level_score=round(level_score, 2),
        proficiency_score=round(proficiency_score, 2),
        color=color,
        icon=icon,
        min_score=min_score,
        max_score=max_score if rank_tier != RankTier.MASTER else None,
    )


def check_rank_up(
    old_level: int, old_proficiency: str,
    new_level: int, new_proficiency: str
) -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Check if user ranked up.
    
    Args:
        old_level: Previous numeric level
        old_proficiency: Previous proficiency level
        new_level: New numeric level
        new_proficiency: New proficiency level
        
    Returns:
        Tuple of (ranked_up, old_rank, new_rank)
    """
    old_rank = calculate_rank(old_level, old_proficiency)
    new_rank = calculate_rank(new_level, new_proficiency)
    
    if old_rank.rank != new_rank.rank:
        return True, old_rank.rank.value, new_rank.rank.value
    
    return False, None, None


def get_rank_info_dict(numeric_level: int, proficiency_level: str) -> dict:
    """Get rank info as a dictionary for API responses."""
    rank_info = calculate_rank(numeric_level, proficiency_level)
    
    return {
        "rank": rank_info.rank.value,
        "rank_name": rank_info.name,
        "rank_score": rank_info.score,
        "level_score": rank_info.level_score,
        "proficiency_score": rank_info.proficiency_score,
        "rank_color": rank_info.color,
        "rank_icon": rank_info.icon,
        "rank_min_score": rank_info.min_score,
        "rank_max_score": rank_info.max_score,
    }


def get_all_ranks() -> list[dict]:
    """Get all rank tier definitions."""
    return [
        {
            "rank": tier.value,
            "name": name,
            "min_score": min_s,
            "max_score": max_s,
            "color": color,
            "icon": icon,
        }
        for tier, name, min_s, max_s, color, icon in RANK_THRESHOLDS
    ]
