"""
Redis Client Module

Provides async Redis client singleton with connection pooling.
Used for token blacklist, caching, and session management.
"""

import logging
from typing import Optional
import redis.asyncio as redis

from app.core.config import settings

logger = logging.getLogger(__name__)


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
    
    @classmethod
    async def connect(cls) -> None:
        """Initialize Redis connection pool."""
        if cls._instance is not None:
            logger.warning("Redis already connected")
            return
        
        try:
            cls._instance = redis.from_url(
                settings.REDIS_URL,
                password=settings.REDIS_PASSWORD,
                encoding="utf-8",
                decode_responses=True,
            )
            # Test connection
            await cls._instance.ping()
            cls._connected = True
            logger.info(f"Redis connected: {settings.REDIS_URL}")
        except redis.ConnectionError as e:
            logger.warning(f"Redis connection failed: {e}. Token blacklist will be disabled.")
            cls._instance = None
            cls._connected = False
        except Exception as e:
            logger.error(f"Unexpected Redis error: {e}")
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
    """Get Redis client (for use as FastAPI dependency)."""
    return await RedisClient.get_instance()
