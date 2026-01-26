"""
Health Check Routes
"""

from fastapi import APIRouter
from app.schemas.common import HealthResponse
from app.core.config import settings

router = APIRouter()


@router.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """
    Health check endpoint.
    
    Returns application status and version.
    """
    return HealthResponse(
        status="healthy",
        message=f"{settings.APP_NAME} is running",
        version="1.0.0"
    )


@router.get("/ping", tags=["Health"])
async def ping():
    """Simple ping endpoint."""
    return {"message": "pong"}
