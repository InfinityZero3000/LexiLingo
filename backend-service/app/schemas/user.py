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
    
    # Level & Rank fields
    total_xp: int = 0
    numeric_level: int = 1
    rank: str = "bronze"

    # RBAC (admin console)
    role_slug: str = "user"
    role_level: int = 0
    is_admin: bool = False
    is_super_admin: bool = False
    
    # RBAC
    role_id: Optional[UUID4] = None
    role_slug: Optional[str] = None  # Populated from role relationship
    
    class Config:
        from_attributes = True


class UserInDB(UserResponse):
    """Schema for user in database (includes sensitive data)."""
    hashed_password: str
    updated_at: datetime


class AdminUserUpdate(BaseModel):
    """Admin update for user (role/status)."""
    role_slug: Optional[str] = None
    is_active: Optional[bool] = None
    display_name: Optional[str] = None


class AdminUserListItem(BaseModel):
    """Admin view of user list."""
    id: UUID4
    email: EmailStr
    username: str
    display_name: Optional[str] = None
    is_active: bool
    is_verified: bool
    role_slug: str = "user"
    role_level: int = 0
    created_at: datetime
    last_login: Optional[datetime] = None

    class Config:
        from_attributes = True
