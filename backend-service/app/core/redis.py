"""
Redis Client Module

Provides async Redis client singleton with connection pooling.
Used for token blacklist, caching, and session management.
"""

import logging
import re
from typing import Optional
import redis.asyncio as redis

from app.core.config import settings

logger = logging.getLogger(__name__)

_CREDENTIALS_IN_URL = re.compile(r"//[^@/]*@")


def _redact_url(url: str) -> str:
    """Strip embedded user:password from a connection URL before logging."""
    return _CREDENTIALS_IN_URL.sub("//***@", url)


class RedisClient:
    """
    Async Redis client singleton with connection pooling.
    
    Usage:
        # Connect on app startup
        await RedisClient.connect()
        
        # Get client instance
        client = await RedisClient.get_instance()
        await client.set("key", "value")
        
        # Close on app shutdown
        await RedisClient.close()
    """
    
    _instance: Optional[redis.Redis] = None
    _connected: bool = False
    
    _VALID_SCHEMES = ("redis://", "rediss://", "unix://")

    @classmethod
    async def connect(cls) -> None:
        """Initialize Redis connection pool."""
        if cls._instance is not None:
            logger.warning("Redis already connected")
            return

        url = settings.REDIS_URL or ""
        if not any(url.startswith(s) for s in cls._VALID_SCHEMES):
            logger.warning(
                "REDIS_URL not configured or has an invalid scheme — Redis disabled. "
                "Token blacklist and caching will be skipped."
            )
            cls._connected = False
            return

        try:
            cls._instance = redis.from_url(
                url,
                password=settings.REDIS_PASSWORD,
                encoding="utf-8",
                decode_responses=True,
            )
            # Test connection
            await cls._instance.ping()
            cls._connected = True
            logger.info(f"Redis connected: {_redact_url(url)}")
        except redis.ConnectionError as e:
            logger.warning(f"Redis connection failed: {e}. Token blacklist will be disabled.")
            cls._instance = None
            cls._connected = False
        except Exception as e:
            logger.warning(f"Redis unavailable: {e}. Token blacklist will be disabled.")
            cls._instance = None
            cls._connected = False
    
    @classmethod
    async def get_instance(cls) -> Optional[redis.Redis]:
        """
        Get Redis client instance.
        
        Returns:
            Redis client or None if not connected
        """
        return cls._instance if cls._connected else None
    
    @classmethod
    async def close(cls) -> None:
        """Close Redis connection."""
        if cls._instance is not None:
            try:
                await cls._instance.close()
                logger.info("Redis connection closed")
            except Exception as e:
                logger.error(f"Error closing Redis: {e}")
            finally:
                cls._instance = None
                cls._connected = False
    
    @classmethod
    def is_connected(cls) -> bool:
        """Check if Redis is connected."""
        return cls._connected


# Convenience function for FastAPI dependency injection
async def get_redis() -> Optional[redis.Redis]:
    """Get Redis client (for use as FastAPI dependency).

    Does NOT connect lazily — RedisClient.connect() is called once by the
    FastAPI lifespan at process startup. A process that never runs that
    lifespan (a Celery worker) must call RedisClient.connect() itself before
    its first use; see app.tasks.event_worker for that bootstrap. Making
    this getter auto-connect would mean any caller — including a route
    handler under test with no Redis mocked — silently opens a real
    connection on first use, which is worse than a clear None.
    """
    return await RedisClient.get_instance()
