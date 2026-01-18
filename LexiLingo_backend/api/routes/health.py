"""
Health check routes
"""

from fastapi import APIRouter
from datetime import datetime

from api.core.database import mongodb_manager
from api.core.redis_client import RedisClient
from api.core.config import settings
from api.models.schemas import HealthCheck

router = APIRouter()


@router.get("/health", response_model=HealthCheck)
async def health_check():
    """
    Comprehensive health check endpoint.
    
    Checks:
    - MongoDB connection
    - Redis connection
    - API status
    
    Works even when services are down (graceful degradation).
    """
    # Check MongoDB
    mongodb_ok = False
    try:
        if mongodb_manager.is_connected:
            await mongodb_manager.client.admin.command("ping")
            mongodb_ok = True
    except Exception:
        pass
    
    # Check Redis
    redis_ok = False
    try:
        redis = await RedisClient.get_instance()
        if redis:
            await redis.ping()
            redis_ok = True
    except Exception:
        pass
    
    # AI Model API (DL-Model-Support)
    ai_model_ok = False  # Will be checked when integrated
    
    return HealthCheck(
        status="healthy" if (mongodb_ok and redis_ok) else "degraded",
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
