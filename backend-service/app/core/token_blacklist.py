"""
Token Blacklist Service

Redis-backed token blacklist for secure logout functionality.
Blacklisted tokens are automatically expired based on their remaining TTL.
"""

import logging
from datetime import datetime
from typing import Optional

from app.core.redis import RedisClient
from app.core.config import settings

logger = logging.getLogger(__name__)


class TokenBlacklist:
    """
    Token blacklist service using Redis.
    
    Provides methods to:
    - Add tokens to blacklist (on logout)
    - Check if token is blacklisted (on each request)
    
    Tokens are stored with TTL matching their expiration time,
    so they automatically clean up after expiring.
    """
    
    PREFIX = "blacklist:token:"
    
    @classmethod
    async def add(
        cls,
        token: str,
        expires_at: Optional[datetime] = None,
        user_id: Optional[str] = None
    ) -> bool:
        """
        Add token to blacklist.
        
        Args:
            token: The JWT token to blacklist
            expires_at: Token expiration time (to calculate TTL)
            user_id: Optional user ID for logging
            
        Returns:
            True if successfully blacklisted, False otherwise
        """
        redis_client = await RedisClient.get_instance()
        
        if redis_client is None:
            logger.warning("Redis not available - token blacklist disabled")
            return False
        
        try:
            # Calculate TTL - either from token expiry or config default
            if expires_at:
                ttl_seconds = int((expires_at - datetime.utcnow()).total_seconds())
                # Add buffer to ensure blacklist outlives token
                ttl_seconds = max(ttl_seconds + 60, 60)
            else:
                ttl_seconds = settings.TOKEN_BLACKLIST_EXPIRE_HOURS * 3600
            
            # Use token hash as key (first 16 chars) for efficiency
            token_key = cls._get_key(token)
            
            # Store with metadata
            value = user_id or "unknown"
            await redis_client.setex(token_key, ttl_seconds, value)
            
            logger.info(f"Token blacklisted for user {user_id} (TTL: {ttl_seconds}s)")
            return True
            
        except Exception as e:
            logger.error(f"Failed to blacklist token: {e}")
            return False
    
    @classmethod
    async def is_blacklisted(cls, token: str) -> bool:
        """
        Check if token is blacklisted.
        
        Args:
            token: The JWT token to check
            
        Returns:
            True if blacklisted, False otherwise
        """
        redis_client = await RedisClient.get_instance()
        
        if redis_client is None:
            # If Redis not available, allow token (fail open)
            # In production, consider failing closed instead
            return False
        
        try:
            token_key = cls._get_key(token)
            exists = await redis_client.exists(token_key)
            return bool(exists)
            
        except Exception as e:
            logger.error(f"Failed to check blacklist: {e}")
            # Fail open on error (allow request)
            return False
    
    @classmethod
    async def remove(cls, token: str) -> bool:
        """
        Remove token from blacklist (rarely needed).
        
        Args:
            token: The JWT token to remove
            
        Returns:
            True if removed, False otherwise
        """
        redis_client = await RedisClient.get_instance()
        
        if redis_client is None:
            return False
        
        try:
            token_key = cls._get_key(token)
            await redis_client.delete(token_key)
            return True
        except Exception as e:
            logger.error(f"Failed to remove from blacklist: {e}")
            return False
    
    @classmethod
    def _get_key(cls, token: str) -> str:
        """Generate Redis key from token (uses hash prefix for efficiency)."""
        # Use last 32 chars of token as unique identifier
        # This avoids storing the full token and is collision-resistant
        token_suffix = token[-32:] if len(token) > 32 else token
        return f"{cls.PREFIX}{token_suffix}"
