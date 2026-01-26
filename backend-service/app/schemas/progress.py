"""
Progress Schemas
Pydantic schemas for progress tracking endpoints
Enhanced for roadmap/learning path UI
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from uuid import UUID
from pydantic import BaseModel, Field, validator
from enum import Enum


class QuestionType(str, Enum):
    """Question types in lessons"""
    MULTIPLE_CHOICE = "multiple_choice"
    FILL_BLANK = "fill_blank"
    MATCHING = "matching"
    LISTENING = "listening"
    SPEAKING = "speaking"
    TRANSLATION = "translation"


class MasteryLevel(str, Enum):
    """Vocabulary mastery levels for SRS"""
    LEARNING = "learning"
    REVIEWING = "reviewing"
    MASTERED = "mastered"


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


# ============================================================================
# NEW: Lesson Attempt Schemas for Learning Sessions
# ============================================================================

class LessonStartRequest(BaseModel):
    """Request to start a lesson"""
    lesson_id: UUID


class LessonStartResponse(BaseModel):
    """Response when starting a lesson"""
    attempt_id: UUID
    lesson_id: UUID
    started_at: datetime
    total_questions: int
    lives_remaining: int = 3
    hints_available: int = 3
    
    class Config:
        from_attributes = True


class AnswerSubmitRequest(BaseModel):
    """Submit an answer for a question"""
    question_id: UUID
    question_type: QuestionType
    user_answer: str | Dict[str, Any]
    time_spent_ms: int = Field(..., ge=0)
    hint_used: bool = False
    confidence_score: Optional[float] = Field(None, ge=0.0, le=1.0)


class AnswerSubmitResponse(BaseModel):
    """Response after submitting an answer"""
    question_attempt_id: UUID
    is_correct: bool
    correct_answer: Optional[str | Dict[str, Any]] = None
    explanation: Optional[str] = None
    xp_earned: int = 0
    lives_remaining: int
    hints_remaining: int
    current_score: float
    
    class Config:
        from_attributes = True


class LessonCompleteRequest(BaseModel):
    """Request to complete a lesson"""
    attempt_id: UUID


class LessonCompleteResponse(BaseModel):
    """Response when completing a lesson"""
    attempt_id: UUID
    passed: bool
    final_score: float
    total_xp_earned: int
    time_spent_seconds: int
    accuracy: float = Field(..., ge=0.0, le=100.0)
    stars_earned: int = Field(..., ge=0, le=3)
    next_lesson_unlocked: Optional[UUID] = None
    achievements_unlocked: List[UUID] = Field(default_factory=list)
    
    # Stats
    total_questions: int
    correct_answers: int
    wrong_answers: int
    hints_used: int
    
    class Config:
        from_attributes = True


# ============================================================================
# Roadmap UI Schemas
# ============================================================================

class LessonProgressItem(BaseModel):
    """Individual lesson progress for roadmap UI"""
    lesson_id: UUID
    lesson_number: int
    title: str
    description: Optional[str] = None
    
    # Status
    is_locked: bool
    is_current: bool  # Currently active lesson
    is_completed: bool
    
    # Progress metrics
    best_score: Optional[float] = None
    stars_earned: int = Field(0, ge=0, le=3)
    attempts_count: int = 0
    completion_percentage: float = 0.0
    
    # UI display
    icon_url: Optional[str] = None
    background_color: Optional[str] = "#4CAF50"
    
    class Config:
        from_attributes = True


class UnitProgressRoadmap(BaseModel):
    """Unit progress for roadmap display"""
    unit_id: UUID
    unit_number: int
    title: str
    description: Optional[str] = None
    
    # Progress
    total_lessons: int
    completed_lessons: int
    completion_percentage: float
    is_current: bool  # Currently active unit
    
    # Lessons in this unit
    lessons: List[LessonProgressItem]
    
    # UI
    icon_url: Optional[str] = None
    background_color: Optional[str] = "#2196F3"
    
    class Config:
        from_attributes = True


class CourseRoadmapResponse(BaseModel):
    """Complete course roadmap for UI"""
    course_id: UUID
    course_title: str
    level: str
    
    # Overall progress
    total_units: int
    completed_units: int
    total_lessons: int
    completed_lessons: int
    completion_percentage: float
    
    # User stats
    total_xp_earned: int
    current_streak: int
    
    # Roadmap data
    units: List[UnitProgressRoadmap]
    
    class Config:
        from_attributes = True

