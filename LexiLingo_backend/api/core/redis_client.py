"""
Redis client for caching and session management

Following architecture.md:
- Learner profiles (level, errors, sessions)
- Common responses caching
- Conversation history
"""

import redis.asyncio as redis
from typing import Optional, Dict, Any, List
import json
from datetime import timedelta

from api.core.config import settings


class RedisClient:
    """Async Redis client singleton."""
    
    _instance: Optional[redis.Redis] = None
    _pool: Optional[redis.ConnectionPool] = None
    
    @classmethod
    async def get_instance(cls) -> redis.Redis:
        """Get or create Redis instance."""
        if cls._instance is None:
            cls._pool = redis.ConnectionPool(
                host=settings.REDIS_HOST,
                port=settings.REDIS_PORT,
                password=settings.REDIS_PASSWORD,
                db=settings.REDIS_DB,
                decode_responses=True,
                max_connections=10,
                socket_timeout=5,
                socket_connect_timeout=5
            )
            cls._instance = redis.Redis(connection_pool=cls._pool)
            
            # Test connection
            try:
                await cls._instance.ping()
                print(f"Connected to Redis: {settings.REDIS_HOST}:{settings.REDIS_PORT}")
            except Exception as e:
                print(f"Redis connection failed: {e}")
                # Don't fail, use graceful degradation
        
        return cls._instance
    
    @classmethod
    async def close(cls):
        """Close Redis connection."""
        if cls._instance:
            await cls._instance.close()
            cls._instance = None
        if cls._pool:
            await cls._pool.disconnect()
            cls._pool = None


class LearnerProfileCache:
    """
    Cache for learner profiles
    
    Keys:
    - learner:{user_id}:level → "A2" / "B1" / "B2"
    - learner:{user_id}:errors → ["past_tense", "articles"]
    - learner:{user_id}:sessions → Last 10 conversation summaries
    """
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.ttl = timedelta(days=30)
    
    async def get_level(self, user_id: str) -> Optional[str]:
        """Get learner's English level."""
        key = f"learner:{user_id}:level"
        return await self.redis.get(key)
    
    async def set_level(self, user_id: str, level: str):
        """Set learner's English level."""
        key = f"learner:{user_id}:level"
        await self.redis.set(key, level, ex=self.ttl)
    
    async def get_common_errors(self, user_id: str) -> List[str]:
        """Get learner's common error types."""
        key = f"learner:{user_id}:errors"
        errors = await self.redis.lrange(key, 0, -1)
        return errors if errors else []
    
    async def add_error(self, user_id: str, error_type: str):
        """Add error type to learner's common errors."""
        key = f"learner:{user_id}:errors"
        await self.redis.lpush(key, error_type)
        await self.redis.ltrim(key, 0, 19)  # Keep last 20 errors
        await self.redis.expire(key, self.ttl)
    
    async def get_sessions(self, user_id: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Get learner's recent session summaries."""
        key = f"learner:{user_id}:sessions"
        sessions = await self.redis.lrange(key, 0, limit - 1)
        return [json.loads(s) for s in sessions] if sessions else []
    
    async def add_session(self, user_id: str, session_summary: Dict[str, Any]):
        """Add session summary to learner's history."""
        key = f"learner:{user_id}:sessions"
        await self.redis.lpush(key, json.dumps(session_summary))
        await self.redis.ltrim(key, 0, 9)  # Keep last 10 sessions
        await self.redis.expire(key, self.ttl)
    
    async def get_profile(self, user_id: str) -> Dict[str, Any]:
        """Get complete learner profile."""
        level = await self.get_level(user_id)
        errors = await self.get_common_errors(user_id)
        sessions = await self.get_sessions(user_id)
        
        return {
            "user_id": user_id,
            "level": level or "B1",  # Default
            "common_errors": errors,
            "recent_sessions": sessions
        }


class ResponseCache:
    """
    Cache for common AI responses
    
    Keys:
    - response:{hash(input)} → JSON response
    """
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.ttl = timedelta(hours=24)
    
    async def get(self, key: str) -> Optional[Dict[str, Any]]:
        """Get cached response."""
        cache_key = f"response:{key}"
        cached = await self.redis.get(cache_key)
        if cached:
            return json.loads(cached)
        return None
    
    async def set(self, key: str, response: Dict[str, Any]):
        """Cache response."""
        cache_key = f"response:{key}"
        await self.redis.set(
            cache_key,
            json.dumps(response),
            ex=self.ttl
        )
    
    async def invalidate(self, key: str):
        """Invalidate cached response."""
        cache_key = f"response:{key}"
        await self.redis.delete(cache_key)


class ConversationCache:
    """
    Cache for conversation history (sliding window)
    
    Keys:
    - conversation:{session_id}:history → Last 5 turns
    """
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.ttl = timedelta(hours=2)
        self.max_turns = 5
    
    async def add_turn(
        self,
        session_id: str,
        user_message: str,
        ai_response: str,
        metadata: Optional[Dict[str, Any]] = None
    ):
        """Add conversation turn."""
        key = f"conversation:{session_id}:history"
        
        turn = {
            "user": user_message,
            "ai": ai_response,
            "metadata": metadata or {}
        }
        
        await self.redis.lpush(key, json.dumps(turn))
        await self.redis.ltrim(key, 0, self.max_turns - 1)  # Keep last 5 turns
        await self.redis.expire(key, self.ttl)
    
    async def get_history(self, session_id: str) -> List[Dict[str, Any]]:
        """Get conversation history."""
        key = f"conversation:{session_id}:history"
        history = await self.redis.lrange(key, 0, -1)
        return [json.loads(turn) for turn in reversed(history)] if history else []
    
    async def clear(self, session_id: str):
        """Clear conversation history."""
        key = f"conversation:{session_id}:history"
        await self.redis.delete(key)


async def get_redis() -> redis.Redis:
    """Dependency injection helper for Redis."""
    return await RedisClient.get_instance()


async def get_learner_cache() -> LearnerProfileCache:
    """Get learner profile cache."""
    redis_client = await get_redis()
    return LearnerProfileCache(redis_client)


async def get_response_cache() -> ResponseCache:
    """Get response cache."""
    redis_client = await get_redis()
    return ResponseCache(redis_client)


async def get_conversation_cache() -> ConversationCache:
    """Get conversation cache."""
    redis_client = await get_redis()
    return ConversationCache(redis_client)
