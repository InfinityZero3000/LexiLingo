"""
Redis client for caching and session management

Following architecture.md:
- Learner profiles (level, errors, sessions)
- Common responses caching
- Conversation history
"""

import asyncio
import logging
import os
import redis.asyncio as redis
from redis.exceptions import ConnectionError as RedisConnectionError, TimeoutError as RedisTimeoutError
from typing import Optional, Dict, Any, List, Callable, Awaitable, TypeVar
import json
from datetime import timedelta

from api.core.config import settings


logger = logging.getLogger(__name__)
T = TypeVar("T")


class RedisClient:
    """Async Redis client singleton."""
    
    _instance: Optional[redis.Redis] = None
    _pool: Optional[redis.ConnectionPool] = None
    _max_retries: int = 10

    @classmethod
    def _benchmark_fail_fast(cls) -> bool:
        value = os.getenv("BENCHMARK_REDIS_FAIL_FAST", "")
        return value.lower() in {"1", "true", "yes", "on"}

    @classmethod
    def _benchmark_redis_disabled(cls) -> bool:
        value = os.getenv("BENCHMARK_REDIS_DISABLED")
        if value is not None and value.strip():
            return value.lower() in {"1", "true", "yes", "on"}
        return cls._benchmark_fail_fast()

    @classmethod
    def _effective_max_retries(cls) -> int:
        if cls._benchmark_fail_fast():
            raw = os.getenv("BENCHMARK_REDIS_MAX_RETRIES", "1")
        else:
            raw = os.getenv("REDIS_MAX_RETRIES", str(cls._max_retries))
        try:
            return max(1, int(raw))
        except ValueError:
            return cls._max_retries

    @classmethod
    def _socket_timeouts(cls) -> tuple[float, float]:
        if cls._benchmark_fail_fast():
            connect_raw = os.getenv("BENCHMARK_REDIS_CONNECT_TIMEOUT", "0.2")
            op_raw = os.getenv("BENCHMARK_REDIS_SOCKET_TIMEOUT", "0.2")
        else:
            connect_raw = os.getenv("REDIS_CONNECT_TIMEOUT", "5")
            op_raw = os.getenv("REDIS_SOCKET_TIMEOUT", "5")

        try:
            connect_timeout = max(0.05, float(connect_raw))
        except ValueError:
            connect_timeout = 5.0
        try:
            socket_timeout = max(0.05, float(op_raw))
        except ValueError:
            socket_timeout = 5.0
        return connect_timeout, socket_timeout

    @classmethod
    async def _create_instance(cls) -> redis.Redis:
        """Create a fresh Redis client and verify connectivity."""
        password = settings.REDIS_PASSWORD if settings.REDIS_PASSWORD else None
        socket_connect_timeout, socket_timeout = cls._socket_timeouts()

        cls._pool = redis.ConnectionPool(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            password=password,
            db=settings.REDIS_DB,
            decode_responses=True,
            max_connections=10,
            socket_timeout=socket_timeout,
            socket_connect_timeout=socket_connect_timeout,
            health_check_interval=30,
        )
        cls._instance = redis.Redis(connection_pool=cls._pool)
        await cls._instance.ping()
        logger.info("Connected to Redis: %s:%s", settings.REDIS_HOST, settings.REDIS_PORT)
        return cls._instance

    @classmethod
    async def _reset(cls) -> None:
        """Drop existing client/pool so next attempt builds clean connections."""
        if cls._instance:
            try:
                await cls._instance.aclose()
            except Exception as _exc:
                logger.debug("[redis_client] ignored: %s", _exc)
                pass
            cls._instance = None
        if cls._pool:
            try:
                await cls._pool.disconnect()
            except Exception as _exc:
                logger.debug("[redis_client] ignored: %s", _exc)
                pass
            cls._pool = None

    @classmethod
    async def reconnect(cls) -> redis.Redis:
        """Reconnect to Redis with capped retries.

        Raises RuntimeError after retry budget is exhausted.
        """
        if cls._benchmark_redis_disabled():
            await cls._reset()
            raise RuntimeError("Redis disabled for benchmark")

        last_exc: Optional[Exception] = None
        max_retries = cls._effective_max_retries()
        for attempt in range(1, max_retries + 1):
            try:
                await cls._reset()
                return await cls._create_instance()
            except Exception as exc:
                last_exc = exc
                logger.warning(
                    "Redis reconnect attempt %s/%s failed: %s",
                    attempt,
                    max_retries,
                    exc,
                )
                if attempt < max_retries:
                    await asyncio.sleep(min(0.2 * attempt, 2.0))

        raise RuntimeError(
            f"Redis reconnect failed after {max_retries} attempts"
        ) from last_exc
    
    @classmethod
    async def get_instance(cls) -> redis.Redis:
        """Get Redis instance; auto-reconnect up to retry budget when unhealthy."""
        if cls._benchmark_redis_disabled():
            await cls._reset()
            raise RuntimeError("Redis disabled for benchmark")

        if cls._instance is None:
            return await cls.reconnect()

        try:
            await cls._instance.ping()
            return cls._instance
        except Exception:
            return await cls.reconnect()

    @classmethod
    async def execute_with_reconnect(
        cls,
        operation: Callable[[redis.Redis], Awaitable[T]],
    ) -> T:
        """Execute a Redis operation with auto-reconnect retry policy.

        Retries connection/timeouts up to 10 times, then raises RuntimeError.
        """
        last_exc: Optional[Exception] = None
        max_retries = cls._effective_max_retries()
        for attempt in range(1, max_retries + 1):
            try:
                client = await cls.get_instance()
                return await operation(client)
            except (RedisConnectionError, RedisTimeoutError) as exc:
                last_exc = exc
                logger.warning(
                    "Redis operation failed (attempt %s/%s), reconnecting: %s",
                    attempt,
                    max_retries,
                    exc,
                )
                if attempt < max_retries:
                    await cls.reconnect()
                    await asyncio.sleep(min(0.2 * attempt, 2.0))

        raise RuntimeError(
            f"Redis operation failed after {max_retries} reconnect attempts"
        ) from last_exc
    
    @classmethod
    async def close(cls):
        """Close Redis connection."""
        await cls._reset()


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
        self.ttl = timedelta(days=7)  # 7 days is sufficient; 30 days wastes memory

    async def _exec(self, operation: Callable[[redis.Redis], Awaitable[T]]) -> T:
        result = await RedisClient.execute_with_reconnect(operation)
        self.redis = await RedisClient.get_instance()
        return result
    
    async def get_level(self, user_id: str) -> Optional[str]:
        """Get learner's English level."""
        key = f"learner:{user_id}:level"
        return await self._exec(lambda r: r.get(key))
    
    async def set_level(self, user_id: str, level: str):
        """Set learner's English level."""
        key = f"learner:{user_id}:level"
        await self._exec(lambda r: r.set(key, level, ex=self.ttl))
    
    async def get_common_errors(self, user_id: str) -> List[str]:
        """Get learner's common error types."""
        key = f"learner:{user_id}:errors"
        errors = await self._exec(lambda r: r.lrange(key, 0, -1))
        return errors if errors else []
    
    async def add_error(self, user_id: str, error_type: str):
        """Add error type to learner's common errors."""
        key = f"learner:{user_id}:errors"
        await self._exec(lambda r: r.lpush(key, error_type))
        await self._exec(lambda r: r.ltrim(key, 0, 19))  # Keep last 20 errors
        await self._exec(lambda r: r.expire(key, self.ttl))
    
    async def get_sessions(self, user_id: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Get learner's recent session summaries."""
        key = f"learner:{user_id}:sessions"
        sessions = await self._exec(lambda r: r.lrange(key, 0, limit - 1))
        return [json.loads(s) for s in sessions] if sessions else []
    
    async def add_session(self, user_id: str, session_summary: Dict[str, Any]):
        """Add session summary to learner's history."""
        key = f"learner:{user_id}:sessions"
        await self._exec(lambda r: r.lpush(key, json.dumps(session_summary)))
        await self._exec(lambda r: r.ltrim(key, 0, 9))  # Keep last 10 sessions
        await self._exec(lambda r: r.expire(key, self.ttl))
    
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
        self.ttl = timedelta(hours=2)  # 2 hours; 24h caused unbounded accumulation

    async def _exec(self, operation: Callable[[redis.Redis], Awaitable[T]]) -> T:
        result = await RedisClient.execute_with_reconnect(operation)
        self.redis = await RedisClient.get_instance()
        return result
    
    async def get(self, key: str) -> Optional[Dict[str, Any]]:
        """Get cached response."""
        cache_key = f"response:{key}"
        cached = await self._exec(lambda r: r.get(cache_key))
        if cached:
            return json.loads(cached)
        return None
    
    async def set(self, key: str, response: Dict[str, Any]):
        """Cache response."""
        cache_key = f"response:{key}"
        await self._exec(
            lambda r: r.set(
                cache_key,
                json.dumps(response),
                ex=self.ttl,
            )
        )
    
    async def invalidate(self, key: str):
        """Invalidate cached response."""
        cache_key = f"response:{key}"
        await self._exec(lambda r: r.delete(cache_key))


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

    async def _exec(self, operation: Callable[[redis.Redis], Awaitable[T]]) -> T:
        result = await RedisClient.execute_with_reconnect(operation)
        self.redis = await RedisClient.get_instance()
        return result
    
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

        await self._exec(lambda r: r.lpush(key, json.dumps(turn)))
        await self._exec(lambda r: r.ltrim(key, 0, self.max_turns - 1))  # Keep last 5 turns
        await self._exec(lambda r: r.expire(key, self.ttl))
    
    async def get_history(self, session_id: str) -> List[Dict[str, Any]]:
        """Get conversation history."""
        key = f"conversation:{session_id}:history"
        history = await self._exec(lambda r: r.lrange(key, 0, -1))
        return [json.loads(turn) for turn in reversed(history)] if history else []
    
    async def clear(self, session_id: str):
        """Clear conversation history."""
        key = f"conversation:{session_id}:history"
        await self._exec(lambda r: r.delete(key))


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
