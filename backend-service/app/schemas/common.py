"""
Common Schemas

Reusable schemas across the application
"""

from typing import Optional
from pydantic import BaseModel, Field


class MessageResponse(BaseModel):
    """Generic message response."""
    message: str
    detail: Optional[str] = None


class PaginationParams(BaseModel):
    """Pagination query parameters."""
    skip: int = Field(0, ge=0, description="Number of items to skip")
    limit: int = Field(100, ge=1, le=100, description="Number of items to return")


class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    message: str
    version: str
