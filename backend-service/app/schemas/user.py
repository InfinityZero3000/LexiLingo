"""
User Schemas
"""

from typing import Optional
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field, UUID4


class UserBase(BaseModel):
    """Base user schema."""
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=50)
    display_name: Optional[str] = None
    native_language: str = "vi"
    target_language: str = "en"
    level: str = "beginner"


class UserCreate(UserBase):
    """Schema for user registration."""
    password: str = Field(..., min_length=8, max_length=100)


class UserUpdate(BaseModel):
    """Schema for user profile update."""
    display_name: Optional[str] = None
    avatar_url: Optional[str] = None
    native_language: Optional[str] = None
    target_language: Optional[str] = None
    level: Optional[str] = None


class UserResponse(UserBase):
    """Schema for user response (public info)."""
    id: UUID4
    avatar_url: Optional[str] = None
    is_active: bool
    is_verified: bool
    created_at: datetime
    last_login: Optional[datetime] = None
    
    class Config:
        from_attributes = True


class UserInDB(UserResponse):
    """Schema for user in database (includes sensitive data)."""
    hashed_password: str
    updated_at: datetime
