"""
Course Schemas

Request and response schemas for Course-related endpoints.
Follows the envelope pattern defined in APP_DEVELOPMENT_PLAN.md.
"""

from typing import Optional, List
from datetime import datetime
from pydantic import BaseModel, Field, validator
import uuid


# =====================
# Course Schemas
# =====================

class CourseBase(BaseModel):
    """Base course schema with common fields."""
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    language: str = Field(..., min_length=2, max_length=10)
    level: str = Field(..., description="CEFR level: A1, A2, B1, B2, C1, C2")
    tags: Optional[List[str]] = Field(default_factory=list)
    thumbnail_url: Optional[str] = Field(None, max_length=500)
    
    @validator('level')
    def validate_level(cls, v):
        allowed_levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
        if v not in allowed_levels:
            raise ValueError(f'Level must be one of {allowed_levels}')
        return v


class CourseCreate(CourseBase):
    """Schema for creating a new course (admin only)."""
    is_published: bool = False


class CourseUpdate(BaseModel):
    """Schema for updating a course (admin only)."""
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    language: Optional[str] = Field(None, min_length=2, max_length=10)
    level: Optional[str] = None
    tags: Optional[List[str]] = None
    thumbnail_url: Optional[str] = Field(None, max_length=500)
    is_published: Optional[bool] = None
    
    @validator('level')
    def validate_level(cls, v):
        if v is not None:
            allowed_levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
            if v not in allowed_levels:
                raise ValueError(f'Level must be one of {allowed_levels}')
        return v


class CourseResponse(CourseBase):
    """Schema for course response."""
    id: uuid.UUID
    total_xp: int = 0
    estimated_duration: int = 0  # minutes
    total_lessons: int = 0
    is_published: bool
    created_at: datetime
    updated_at: datetime
    
    # Additional fields for enrolled users
    is_enrolled: Optional[bool] = None
    user_progress: Optional[float] = None  # 0-100%
    
    class Config:
        from_attributes = True


class CourseListItem(BaseModel):
    """Lightweight course schema for list views."""
    id: uuid.UUID
    title: str
    description: Optional[str] = None
    language: str
    level: str
    tags: Optional[List[str]] = Field(default_factory=list)
    thumbnail_url: Optional[str] = None
    total_lessons: int = 0
    total_xp: int = 0
    estimated_duration: int = 0
    is_enrolled: Optional[bool] = None
    
    class Config:
        from_attributes = True


# =====================
# Unit Schemas
# =====================

class UnitBase(BaseModel):
    """Base unit schema."""
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    order_index: int = Field(..., ge=0)
    background_color: Optional[str] = Field(None, max_length=20)
    icon_url: Optional[str] = Field(None, max_length=500)


class UnitCreate(UnitBase):
    """Schema for creating a new unit (admin only)."""
    course_id: uuid.UUID


class UnitUpdate(BaseModel):
    """Schema for updating a unit (admin only)."""
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    order_index: Optional[int] = Field(None, ge=0)
    background_color: Optional[str] = Field(None, max_length=20)
    icon_url: Optional[str] = Field(None, max_length=500)


class UnitResponse(UnitBase):
    """Schema for unit response."""
    id: uuid.UUID
    course_id: uuid.UUID
    total_lessons: int = 0
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


# =====================
# Lesson Schemas
# =====================

class LessonBase(BaseModel):
    """Base lesson schema."""
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    order_index: int = Field(..., ge=0)
    lesson_type: str = Field(..., description="lesson, practice, review, test")
    xp_reward: int = Field(default=10, ge=0)
    pass_threshold: int = Field(default=80, ge=0, le=100)
    
    @validator('lesson_type')
    def validate_lesson_type(cls, v):
        allowed_types = ['lesson', 'practice', 'review', 'test']
        if v not in allowed_types:
            raise ValueError(f'Lesson type must be one of {allowed_types}')
        return v


class LessonCreate(LessonBase):
    """Schema for creating a new lesson (admin only)."""
    unit_id: uuid.UUID
    prerequisites: Optional[List[uuid.UUID]] = Field(default_factory=list)


class LessonUpdate(BaseModel):
    """Schema for updating a lesson (admin only)."""
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    order_index: Optional[int] = Field(None, ge=0)
    lesson_type: Optional[str] = None
    xp_reward: Optional[int] = Field(None, ge=0)
    pass_threshold: Optional[int] = Field(None, ge=0, le=100)
    prerequisites: Optional[List[uuid.UUID]] = None
    
    @validator('lesson_type')
    def validate_lesson_type(cls, v):
        if v is not None:
            allowed_types = ['lesson', 'practice', 'review', 'test']
            if v not in allowed_types:
                raise ValueError(f'Lesson type must be one of {allowed_types}')
        return v


class LessonResponse(LessonBase):
    """Schema for lesson response."""
    id: uuid.UUID
    unit_id: uuid.UUID
    prerequisites: List[uuid.UUID] = Field(default_factory=list)
    total_exercises: int = 0
    is_locked: Optional[bool] = None
    is_completed: Optional[bool] = None
    best_score: Optional[int] = None
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


# =====================
# Course Detail with Units/Lessons
# =====================

class LessonInUnit(BaseModel):
    """Lesson info within a unit."""
    id: uuid.UUID
    title: str
    order_index: int
    lesson_type: str
    xp_reward: int
    is_locked: Optional[bool] = None
    is_completed: Optional[bool] = None
    
    class Config:
        from_attributes = True


class UnitWithLessons(BaseModel):
    """Unit with its lessons."""
    id: uuid.UUID
    title: str
    description: Optional[str] = None
    order_index: int
    background_color: Optional[str] = None
    icon_url: Optional[str] = None
    lessons: List[LessonInUnit] = Field(default_factory=list)
    
    class Config:
        from_attributes = True


class CourseDetailResponse(CourseResponse):
    """Detailed course response with units and lessons."""
    units: List[UnitWithLessons] = Field(default_factory=list)


# =====================
# Enrollment Schemas
# =====================

class EnrollmentResponse(BaseModel):
    """Schema for enrollment confirmation."""
    course_id: uuid.UUID
    user_id: uuid.UUID
    enrolled_at: datetime
    message: str = "Successfully enrolled in course"
    
    class Config:
        from_attributes = True
    is_published: bool
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class CourseWithLessons(CourseResponse):
    """Schema for course with lessons."""
    lessons: List[LessonResponse] = []
