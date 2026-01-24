"""
Common Schemas

Reusable schemas across the application
Following the standardized envelope pattern from APP_DEVELOPMENT_PLAN.md
"""

from typing import Any, Dict, Generic, Optional, TypeVar
from datetime import datetime
from pydantic import BaseModel, Field
import uuid


DataT = TypeVar("DataT")


class RequestMeta(BaseModel):
    """Metadata for all API responses."""
    request_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class PaginationMeta(BaseModel):
    """Pagination metadata."""
    page: int = Field(ge=1, description="Current page number")
    page_size: int = Field(ge=1, le=100, description="Items per page")
    total: int = Field(ge=0, description="Total number of items")
    total_pages: int = Field(ge=0, description="Total number of pages")


class ApiResponse(BaseModel, Generic[DataT]):
    """
    Standard success response envelope.
    
    Example:
    {
        "data": {...},
        "meta": {
            "request_id": "123e4567-e89b-12d3-a456-426614174000",
            "timestamp": "2026-01-24T10:20:30Z"
        }
    }
    """
    data: DataT
    meta: RequestMeta = Field(default_factory=RequestMeta)


class PaginatedResponse(BaseModel, Generic[DataT]):
    """
    Standard paginated response envelope.
    
    Example:
    {
        "data": [...],
        "pagination": {
            "page": 1,
            "page_size": 20,
            "total": 123,
            "total_pages": 7
        },
        "meta": {
            "request_id": "...",
            "timestamp": "..."
        }
    }
    """
    data: list[DataT]
    pagination: PaginationMeta
    meta: RequestMeta = Field(default_factory=RequestMeta)


class ErrorDetail(BaseModel):
    """Error details."""
    code: str = Field(description="Error code (e.g., AUTH_INVALID, VALIDATION_ERROR)")
    message: str = Field(description="Human-readable error message")
    details: Optional[Dict[str, Any]] = Field(default=None, description="Additional error context")


class ErrorResponse(BaseModel):
    """
    Standard error response envelope.
    
    Example:
    {
        "error": {
            "code": "AUTH_INVALID",
            "message": "Invalid credentials",
            "details": {"field": "password"}
        },
        "meta": {
            "request_id": "...",
            "timestamp": "..."
        }
    }
    """
    error: ErrorDetail
    meta: RequestMeta = Field(default_factory=RequestMeta)


class MessageResponse(BaseModel):
    """Generic message response."""
    message: str
    detail: Optional[str] = None


class PaginationParams(BaseModel):
    """Pagination query parameters."""
    skip: int = Field(0, ge=0, description="Number of items to skip")
    limit: int = Field(100, ge=1, le=100, description="Number of items to return")
    page: int = Field(1, ge=1, description="Page number")
    page_size: int = Field(20, ge=1, le=100, description="Items per page")


class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    message: str
    version: str


# Standard error codes
class ErrorCodes:
    """Standard error codes for the API."""
    
    # Authentication errors
    AUTH_INVALID = "AUTH_INVALID"
    AUTH_EXPIRED = "AUTH_EXPIRED"
    AUTH_FORBIDDEN = "AUTH_FORBIDDEN"
    AUTH_MISSING = "AUTH_MISSING"
    
    # Validation errors
    VALIDATION_ERROR = "VALIDATION_ERROR"
    INVALID_INPUT = "INVALID_INPUT"
    
    # Resource errors
    NOT_FOUND = "NOT_FOUND"
    ALREADY_EXISTS = "ALREADY_EXISTS"
    CONFLICT = "CONFLICT"
    
    # Rate limiting
    RATE_LIMITED = "RATE_LIMITED"
    
    # Server errors
    INTERNAL_ERROR = "INTERNAL_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
