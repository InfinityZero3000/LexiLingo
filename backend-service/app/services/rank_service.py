"""
Rank Service

Calculates user rank based on weighted score of:
- Numeric Level (60% weight)
- Proficiency Level A1-C2 (40% weight)

Rank Tiers:
- Bronze: 0-19 points
- Silver: 20-34 points
- Gold: 35-49 points
- Platinum: 50-59 points
- Sapphire: 60-69 points
- Ruby: 70-79 points
- Amethyst: 80-94 points
- Master: 95+ points
"""

from dataclasses import dataclass
from typing import Literal, Optional
from enum import Enum


class RankTier(str, Enum):
    """Rank tier enumeration."""
    BRONZE = "bronze"
    SILVER = "silver"
    GOLD = "gold"
    PLATINUM = "platinum"
    SAPPHIRE = "sapphire"
    RUBY = "ruby"
    AMETHYST = "amethyst"
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
    icon_url: str
    min_score: int
    max_score: Optional[int]


@dataclass(frozen=True)
class RankChange:
    changed: bool
    direction: Literal["promotion", "demotion", "unchanged"]
    old_rank: str
    new_rank: str


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
    (RankTier.BRONZE, "Bronze", 0, 20, "#CD7F32", "🥉", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/1-bronze.png"),
    (RankTier.SILVER, "Silver", 20, 35, "#C0C0C0", "🥈", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/2-silver.png"),
    (RankTier.GOLD, "Gold", 35, 50, "#FFD700", "🥇", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/3-gold.png"),
    (RankTier.PLATINUM, "Platinum", 50, 60, "#E5E4E2", "💎", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/4-platinum.png"),
    (RankTier.SAPPHIRE, "Sapphire", 60, 70, "#4783EB", "🔹", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/5-sapphire.png"),
    (RankTier.RUBY, "Ruby", 70, 80, "#E14242", "🔻", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/6-ruby.png"),
    (RankTier.AMETHYST, "Amethyst", 80, 95, "#9652E3", "🔮", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/7-amethyst.png"),
    (RankTier.MASTER, "Master", 95, 101, "#9966CC", "👑", "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/8-master.png"),
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
    capped_level = max(0, min(numeric_level, 100))
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
    max_score = 20
    color = "#CD7F32"
    icon = "🥉"
    icon_url = "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/1-bronze.png"
    
    for tier, name, min_s, max_s, c, i, u in RANK_THRESHOLDS:
        if min_s <= score < max_s:
            rank_tier = tier
            rank_name = name
            min_score = min_s
            max_score = max_s
            color = c
            icon = i
            icon_url = u
            break
        elif score >= 95:  # Master is special case
            rank_tier = RankTier.MASTER
            rank_name = "Master"
            min_score = 95
            max_score = 100
            color = "#9966CC"
            icon = "👑"
            icon_url = "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo@main/flutter-app/assets/ranking/8-master.png"
            break
    
    # Calculate component scores
    capped_level = max(0, min(numeric_level, 100))
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
        icon_url=icon_url,
        min_score=min_score,
        max_score=max_score if rank_tier != RankTier.MASTER else None,
    )


def check_rank_change(
    old_level: int, old_proficiency: str,
    new_level: int, new_proficiency: str
) -> RankChange:
    """Describe a rank promotion, demotion, or unchanged result."""
    old_rank = calculate_rank(old_level, old_proficiency)
    new_rank = calculate_rank(new_level, new_proficiency)

    old_index = list(RankTier).index(old_rank.rank)
    new_index = list(RankTier).index(new_rank.rank)
    if new_index > old_index:
        direction = "promotion"
    elif new_index < old_index:
        direction = "demotion"
    else:
        direction = "unchanged"

    return RankChange(
        changed=direction != "unchanged",
        direction=direction,
        old_rank=old_rank.rank.value,
        new_rank=new_rank.rank.value,
    )


def apply_rank_info_to_user(user, rank_info: RankInfo) -> None:
    """Persist the user's single rank tier and cached rank score components."""
    user.rank = rank_info.rank.value
    user.rank_score = rank_info.score
    user.rank_level_score = rank_info.level_score
    user.rank_proficiency_score = rank_info.proficiency_score
