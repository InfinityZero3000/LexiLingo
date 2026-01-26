"""
Generic API response schemas
"""

from typing import Generic, TypeVar, Any
from pydantic import BaseModel

T = TypeVar('T')

class ApiResponse(BaseModel, Generic[T]):
    """Generic API response wrapper."""
    success: bool = True
    message: str | None = None
    data: T | None = None
    error: str | None = None
    
    class Config:
        json_schema_extra = {
            "example": {
                "success": True,
                "message": "Operation completed successfully",
                "data": {},
                "error": None
            }
        }
