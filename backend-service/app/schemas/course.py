"""
Course Schemas
"""

from typing import Optional, List
from datetime import datetime
from pydantic import BaseModel, Field, UUID4


class CourseBase(BaseModel):
    """Base course schema."""
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    language: str = Field(..., min_length=2, max_length=10)
    level: str
    thumbnail_url: Optional[str] = None


class CourseCreate(CourseBase):
    """Schema for course creation."""
    pass


class CourseUpdate(BaseModel):
    """Schema for course update."""
    title: Optional[str] = None
    description: Optional[str] = None
    level: Optional[str] = None
    thumbnail_url: Optional[str] = None
    is_published: Optional[bool] = None


class LessonResponse(BaseModel):
    """Schema for lesson response."""
    id: UUID4
    course_id: UUID4
    title: str
    description: Optional[str]
    order_index: int
    estimated_minutes: int
    created_at: datetime
    
    class Config:
        from_attributes = True


class CourseResponse(CourseBase):
    """Schema for course response."""
    id: UUID4
    total_lessons: int
    is_published: bool
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class CourseWithLessons(CourseResponse):
    """Schema for course with lessons."""
    lessons: List[LessonResponse] = []
