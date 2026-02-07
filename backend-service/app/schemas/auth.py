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
    role: Optional[str] = "user"  # Role slug: user, admin, super_admin


class RefreshTokenRequest(BaseModel):
    """Refresh token request."""
    refresh_token: str


class ChangePasswordRequest(BaseModel):
    """Change password request."""
    current_password: str
    new_password: str = Field(..., min_length=8, max_length=100)


# ===== New schemas for missing endpoints =====

class GoogleLoginRequest(BaseModel):
    """Google OAuth login request."""
    id_token: str = Field(..., description="Google ID token from client")
    source: str = Field(default="app", description="Login source: 'app' for Flutter, 'admin' for web admin")


class ForgotPasswordRequest(BaseModel):
    """Forgot password request."""
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    """Reset password with token."""
    token: str = Field(..., description="Password reset token from email")
    new_password: str = Field(..., min_length=8, max_length=100)


class VerifyEmailRequest(BaseModel):
    """Verify email with token."""
    token: str = Field(..., description="Email verification token")


class VerifyEmailResponse(BaseModel):
    """Verify email response."""
    verified: bool
    message: str

