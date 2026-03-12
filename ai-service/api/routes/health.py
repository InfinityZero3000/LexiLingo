"""
Health check routes
"""

import asyncio
import logging
from fastapi import APIRouter, BackgroundTasks
from datetime import datetime

from api.core.database import mongodb_manager
from api.core.redis_client import RedisClient
from api.core.config import settings
from api.models.schemas import HealthCheck

logger = logging.getLogger(__name__)

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
        if mongodb_manager._client is not None:
            await mongodb_manager._client.admin.command("ping")
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
        mongodb="connected" if mongodb_ok else "disconnected",
        redis="connected" if redis_ok else "disconnected",
        version=settings.API_VERSION,
        timestamp=datetime.utcnow()
    )


@router.get("/ping")
async def ping():
    """Simple ping endpoint for quick checks."""
    return {"ping": "pong", "timestamp": datetime.utcnow().isoformat()}


@router.post("/warmup")
async def warmup(background_tasks: BackgroundTasks):
    """
    Trigger background preloading of AI models (chat/STT/TTS).

    Returns immediately; models load asynchronously via ModelGateway.
    Safe to call multiple times — already-loaded models are skipped.
    """
    async def _do_warmup():
        try:
            from api.services.model_gateway import get_model_gateway
            gw = get_model_gateway()
            await gw.preload_models()
            logger.info("Warmup: model preload complete")
        except Exception as e:
            logger.warning(f"Warmup: preload error (non-fatal): {e}")

    background_tasks.add_task(_do_warmup)
    return {"status": "warming_up", "message": "Model preload started in background"}
