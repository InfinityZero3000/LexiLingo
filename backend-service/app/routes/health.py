"""
Health Check Routes
"""

import logging
from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.common import HealthResponse
from app.core.config import settings
from app.core.database import get_db

logger = logging.getLogger(__name__)

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


@router.get("/health/ready", tags=["Health"])
async def readiness_check(db: AsyncSession = Depends(get_db)):
    """
    Readiness probe — verifies DB and Redis connectivity.
    Returns 200 only when all dependencies are reachable.
    """
    checks = {"database": "ok", "redis": "ok"}

    # Database check
    try:
        await db.execute(text("SELECT 1"))
    except Exception as e:
        logger.error("Health check: DB unreachable: %s", e)
        checks["database"] = "unreachable"

    # Redis check
    try:
        from app.core.redis import RedisClient
        redis_client = await RedisClient.get_instance()
        if redis_client:
            await redis_client.ping()  # type: ignore[misc]  # redis.asyncio stubs
        else:
            checks["redis"] = "not configured"
    except Exception as e:
        logger.error("Health check: Redis unreachable: %s", e)
        checks["redis"] = "unreachable"

    all_ok = all(v in ("ok", "not configured") for v in checks.values())
    status_code = 200 if all_ok else 503

    from fastapi.responses import JSONResponse
    return JSONResponse(
        status_code=status_code,
        content={"status": "ready" if all_ok else "degraded", "checks": checks}
    )


@router.get("/ping", tags=["Health"])
async def ping():
    """Simple ping endpoint."""
    return {"message": "pong"}
