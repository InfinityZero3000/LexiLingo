"""
Authentication Schemas
"""

from typing import Optional
from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    """Registration request."""
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=8, max_length=100)
    display_name: Optional[str] = None


class LoginRequest(BaseModel):
    """Login request."""
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    """Token response."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class LoginResponse(TokenResponse):
    """Login response with user info."""
    user_id: str
    username: str
    email: str


class RefreshTokenRequest(BaseModel):
    """Refresh token request."""
    refresh_token: str


class ChangePasswordRequest(BaseModel):
    """Change password request."""
    old_password: str
    new_password: str = Field(..., min_length=8, max_length=100)
