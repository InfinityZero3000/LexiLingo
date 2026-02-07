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


class WeeklyProgressData(BaseModel):
    """
    Weekly progress data for home page chart.
    
    Following agent-skills/language-learning-patterns:
    - progress-learning-streaks: Visual progress improves engagement 3-5x
    """
    day: str = Field(..., description="Day of week (Mon, Tue, Wed, Thu, Fri, Sat, Sun)")
    date: str = Field(..., description="ISO date string (YYYY-MM-DD)")
    xp_earned: int = Field(default=0, description="XP earned on this day")
    lessons_completed: int = Field(default=0, description="Lessons completed")
    study_time_minutes: int = Field(default=0, description="Study time in minutes")
    vocabulary_reviewed: int = Field(default=0, description="Vocabulary items reviewed")
    goal_met: bool = Field(default=False, description="Whether daily goal was met")
    is_today: bool = Field(default=False, description="Whether this is today")


class WeeklyProgressResponse(BaseModel):
    """
    Weekly progress response for home page.
    
    Provides 7-day activity summary with totals and streak info.
    Used for the week progress chart on home page.
    """
    week_progress: list[WeeklyProgressData] = Field(..., description="7-day activity data")
    total_xp: int = Field(default=0, description="Total XP earned this week")
    total_lessons: int = Field(default=0, description="Total lessons completed this week")
    total_study_time: int = Field(default=0, description="Total study time in minutes")
    days_active: int = Field(default=0, description="Number of active days this week")
    current_streak: int = Field(default=0, description="Current streak count")
    longest_streak: int = Field(default=0, description="Longest streak ever")
    week_goal_progress: float = Field(default=0.0, ge=0, le=100, description="Weekly goal progress percentage")


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


class LevelFullResponse(BaseModel):
    """Full level info including numeric level, rank, and proficiency."""
    numeric_level: int = Field(..., description="Gamification level (1, 2, 3...)")
    current_xp_in_level: int = Field(..., description="XP progress within current numeric level")
    xp_for_next_level: int = Field(..., description="XP required to reach next numeric level")
    level_progress_percent: float = Field(..., ge=0, le=100, description="Progress to next level")
    total_xp: int = Field(..., description="Total XP earned")
    proficiency_level: str = Field(..., description="CEFR proficiency code (A1-C2)")
    proficiency_name: str = Field(..., description="Proficiency name (e.g., 'Beginner')")
    rank: str = Field(..., description="Rank tier (bronze, silver, gold, platinum, diamond, master)")
    rank_name: str = Field(..., description="Rank display name")
    rank_score: float = Field(..., description="Weighted rank score (0-100)")
    rank_color: str = Field(default="#CD7F32", description="Rank color hex code")
    rank_icon: str = Field(default="🥉", description="Rank icon emoji")
