"""
Progress Schemas
Pydantic schemas for progress tracking endpoints
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, validator


class LessonCompletionBase(BaseModel):
    """Base lesson completion schema"""
    lesson_id: str = Field(..., description="UUID of the lesson")
    score: float = Field(..., ge=0, le=100, description="Score achieved (0-100)")
    
    @validator('score')
    def validate_score(cls, v):
        if v < 0 or v > 100:
            raise ValueError('Score must be between 0 and 100')
        return v


class LessonCompletionCreate(LessonCompletionBase):
    """Schema for marking a lesson as complete"""
    pass


class LessonCompletionResponse(BaseModel):
    """Response after completing a lesson"""
    lesson_id: str
    is_passed: bool
    score: float
    best_score: float
    xp_earned: int
    total_xp: int
    course_progress: float
    message: str
    
    class Config:
        from_attributes = True


class UserProgressSummary(BaseModel):
    """User's overall progress summary"""
    total_xp: int
    courses_enrolled: int
    courses_completed: int
    lessons_completed: int
    current_streak: int
    longest_streak: int
    achievements_unlocked: int
    
    class Config:
        from_attributes = True


class CourseProgressDetail(BaseModel):
    """Detailed progress for a specific course"""
    course_id: str
    course_title: str
    progress_percentage: float
    lessons_completed: int
    total_lessons: int
    total_xp_earned: int
    started_at: datetime
    last_activity_at: datetime
    estimated_completion_days: Optional[int] = None
    
    class Config:
        from_attributes = True


class CourseProgressResponse(BaseModel):
    """Response with course progress details"""
    course: CourseProgressDetail
    units_progress: list[dict]  # List of unit progress details
    
    class Config:
        from_attributes = True


class UserActivityLog(BaseModel):
    """User activity log entry"""
    date: datetime
    lessons_completed: int
    xp_earned: int
    time_spent_minutes: int
    
    class Config:
        from_attributes = True


class ProgressStatsResponse(BaseModel):
    """Comprehensive progress statistics"""
    summary: UserProgressSummary
    recent_activity: list[UserActivityLog]
    course_progress: list[CourseProgressDetail]
    
    class Config:
        from_attributes = True
