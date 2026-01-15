"""
Health check routes
"""

from fastapi import APIRouter, Depends
from motor.motor_asyncio import AsyncIOMotorDatabase
from datetime import datetime

from api.core.database import get_database
from api.core.config import settings
from api.models.schemas import HealthCheck

router = APIRouter()


@router.get("/health", response_model=HealthCheck)
async def health_check(db: AsyncIOMotorDatabase = Depends(get_database)):
    """
    Comprehensive health check endpoint.
    
    Checks:
    - MongoDB connection
    - Redis connection (if applicable)
    - API status
    """
    # Check MongoDB
    mongodb_ok = False
    try:
        await db.command("ping")
        mongodb_ok = True
    except Exception:
        pass
    
    # Check Redis (TODO: implement when Redis is added)
    redis_ok = True  # Placeholder
    
    # AI Model API (DL-Model-Support)
    ai_model_ok = False  # Will be checked when integrated
    
    return HealthCheck(
        status="healthy" if mongodb_ok else "degraded",
        version=settings.API_VERSION,
        environment=settings.ENVIRONMENT,
        services={
            "mongodb": mongodb_ok,
            "redis": redis_ok,
            "ai_model": ai_model_ok
        }
    )


@router.get("/ping")
async def ping():
    """Simple ping endpoint for quick checks."""
    return {"ping": "pong", "timestamp": datetime.utcnow().isoformat()}
