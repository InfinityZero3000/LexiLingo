"""
Level System Schemas

Schemas for level progression, XP tracking, and user statistics.
"""

from typing import Optional
from datetime import datetime
from pydantic import BaseModel, Field


# =====================
# Level Tier Definitions
# =====================

class LevelTier(BaseModel):
    """Level tier definition."""
    code: str = Field(..., description="Level code (A1, A2, B1, B2, C1, C2)")
    name: str = Field(..., description="Level name (e.g., 'Beginner')")
    min_xp: int = Field(..., description="Minimum XP required")
    max_xp: Optional[int] = Field(None, description="Maximum XP (None for highest tier)")
    color: str = Field(..., description="Hex color code")
    description: str = Field(..., description="Level description")


class LevelStatus(BaseModel):
    """Current level status for a user."""
    current_tier: LevelTier
    total_xp: int
    xp_in_current_tier: int = Field(..., description="XP progress within current tier")
    xp_to_next_tier: Optional[int] = Field(None, description="XP needed for next tier (None if max level)")
    progress_percentage: float = Field(..., ge=0, le=100, description="Progress to next level (0-100)")


# =====================
# User Stats Schemas
# =====================

class UserStatsResponse(BaseModel):
    """User learning statistics."""
    total_xp: int = Field(default=0)
    level: LevelStatus
    
    # Course stats
    courses_enrolled: int = Field(default=0)
    courses_completed: int = Field(default=0)
    
    # Learning stats
    lessons_completed: int = Field(default=0)
    total_study_time: int = Field(default=0, description="Total study time in minutes")
    
    # Streak stats
    current_streak: int = Field(default=0)
    longest_streak: int = Field(default=0)
    
    # Vocabulary stats
    words_learned: int = Field(default=0)
    words_mastered: int = Field(default=0)
    
    # Achievements
    achievements_unlocked: int = Field(default=0)
    
    # Currency
    total_gems: int = Field(default=0)


class WeeklyActivityData(BaseModel):
    """Weekly activity data for charts."""
    day: str = Field(..., description="Day of week (Mon, Tue, etc.)")
    xp: int = Field(..., description="XP earned on this day")
    lessons: int = Field(default=0, description="Lessons completed")
    study_time: int = Field(default=0, description="Study time in minutes")


class WeeklyActivityResponse(BaseModel):
    """Weekly activity response."""
    week_data: list[WeeklyActivityData]
    total_xp: int
    total_lessons: int
    total_study_time: int


# =====================
# XP & Level Operations
# =====================

class XPAwardRequest(BaseModel):
    """Request to award XP to a user."""
    amount: int = Field(..., gt=0, description="Amount of XP to award")
    reason: str = Field(..., description="Reason for XP award (e.g., 'Completed lesson')")
    metadata: Optional[dict] = Field(None, description="Additional metadata")


class XPAwardResponse(BaseModel):
    """Response after awarding XP."""
    total_xp: int
    xp_gained: int
    new_level: LevelStatus
    level_up: bool = Field(default=False, description="True if user leveled up")
    previous_tier: Optional[str] = Field(None, description="Previous tier code if leveled up")


class LevelInfoResponse(BaseModel):
    """Detailed level information."""
    all_tiers: list[LevelTier]
    current_level: LevelStatus
