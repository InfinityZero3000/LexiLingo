"""
Pydantic Schemas

Request/Response models for API validation
"""

from app.schemas.user import UserCreate, UserUpdate, UserResponse, UserInDB
from app.schemas.auth import (
    LoginRequest,
    LoginResponse,
    TokenResponse,
    RegisterRequest,
    RefreshTokenRequest
)
from app.schemas.course import CourseCreate, CourseResponse, LessonResponse
from app.schemas.common import MessageResponse, PaginationParams

__all__ = [
    # User
    "UserCreate",
    "UserUpdate",
    "UserResponse",
    "UserInDB",
    # Auth
    "LoginRequest",
    "LoginResponse",
    "TokenResponse",
    "RegisterRequest",
    "RefreshTokenRequest",
    # Course
    "CourseCreate",
    "CourseResponse",
    "LessonResponse",
    # Common
    "MessageResponse",
    "PaginationParams",
]
