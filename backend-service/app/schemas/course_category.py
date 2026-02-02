"""
Course Category Schemas

Request and response schemas for Course Category endpoints.
"""

from typing import Optional
from datetime import datetime
from pydantic import BaseModel, Field
import uuid


# =====================
# Category Schemas
# =====================

class CourseCategoryBase(BaseModel):
    """Base category schema."""
    name: str = Field(..., min_length=1, max_length=100)
    slug: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    icon: Optional[str] = Field(None, max_length=50)
    color: Optional[str] = Field(None, max_length=20)
    order_index: int = Field(default=0)
    is_active: bool = Field(default=True)


class CourseCategoryCreate(CourseCategoryBase):
    """Schema for creating a new category."""
    pass


class CourseCategoryUpdate(BaseModel):
    """Schema for updating a category."""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    slug: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None
    icon: Optional[str] = Field(None, max_length=50)
    color: Optional[str] = Field(None, max_length=20)
    order_index: Optional[int] = None
    is_active: Optional[bool] = None


class CourseCategoryResponse(CourseCategoryBase):
    """Category response with all fields."""
    id: uuid.UUID
    course_count: int
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class CourseCategoryListItem(BaseModel):
    """Simplified category for list views."""
    id: uuid.UUID
    name: str
    slug: str
    description: Optional[str] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    course_count: int
    
    class Config:
        from_attributes = True
