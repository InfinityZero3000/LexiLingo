"""
API Cache Service — 3-Layer Cache with Quota-Aware Fetching

Layer 1: Redis (hot cache, short TTL)
Layer 2: PostgreSQL (persistent cache, longer TTL)
Layer 3: External API (actual HTTP call)

Before hitting Layer 3, checks QuotaManager thresholds.
Serves stale data when quota is exhausted rather than failing.

Phase 0 Infrastructure: Required by all content features.
"""

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.redis import RedisClient
from app.models.api_cache import APICacheEntry
from app.services.quota_manager import Priority, QuotaManager, QuotaStatus

logger = logging.getLogger(__name__)


class QuotaExhaustedError(Exception):
    """Raised when API quota is fully exhausted and no cache available."""
    
    def __init__(self, api_name: str, reset_time: str):
        self.api_name = api_name
        self.reset_time = reset_time
        super().__init__(
            f"{api_name} quota exhausted. Resets in {reset_time}."
        )


class QuotaNearLimitError(Exception):
    """Raised when request is blocked by near-limit threshold."""
    
    def __init__(self, api_name: str, level: str, message: str):
        self.api_name = api_name
        self.level = level
        super().__init__(f"{api_name} [{level}]: {message}")


@dataclass
class CacheResult:
    """Result from cache lookup with provenance metadata."""
    data: Any
    source: str         # "redis", "db", "api", "db_stale"
    is_stale: bool      # True if data may be outdated


class APICacheService:
    """
    3-layer cache: Redis → PostgreSQL → External API.
    
    Flow: check_redis → check_db → check_quota_threshold → fetch_or_serve_stale.
    
    Usage:
        cache_service = APICacheService(db_session)
        result = await cache_service.get_or_fetch(
            cache_key="news:en:technology:2026-02-24",
            api_name="newsapi",
            fetch_fn=lambda: newsapi_client.get_headlines(category="tech"),
            priority=Priority.MEDIUM,
            redis_ttl=3600,
            db_ttl=21600,
        )
        if result.is_stale:
            # Add X-Data-Freshness header to response
    """
    
    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def get_or_fetch(
        self,
        cache_key: str,
        api_name: str,
        fetch_fn: Callable,
        priority: Priority = Priority.MEDIUM,
        redis_ttl: int = 3600,
        db_ttl: int = 86400,
    ) -> CacheResult:
        """
        Attempt to retrieve data from cache layers, falling through to API.
        
        Args:
            cache_key: Unique cache identifier (e.g. "news:en:tech:2026-02-24")
            api_name: API identifier for quota tracking (e.g. "newsapi")
            fetch_fn: Async callable that fetches from external API
            priority: Request priority level (affects quota threshold behavior)
            redis_ttl: Redis cache time-to-live in seconds
            db_ttl: PostgreSQL "freshness" TTL in seconds
            
        Returns:
            CacheResult with data and provenance info
            
        Raises:
            QuotaExhaustedError: quota fully exhausted, no cache available
            QuotaNearLimitError: near-limit threshold blocks this priority
        """
        redis_key = f"api:{cache_key}"
        
        # ──── Layer 1: Redis (hot cache) ────
        redis = await RedisClient.get_instance()
        if redis is not None:
            try:
                cached = await redis.get(redis_key)
                if cached is not None:
                    logger.debug(f"Cache HIT (redis): {cache_key}")
                    return CacheResult(
                        data=json.loads(cached),
                        source="redis",
                        is_stale=False,
                    )
            except Exception as e:
                logger.warning(f"Redis read error for {cache_key}: {e}")
        
        # ──── Layer 2: PostgreSQL (persistent cache) ────
        db_entry = await self._get_db_entry(cache_key)
        
        if db_entry is not None and not db_entry.is_expired(db_ttl):
            # Fresh DB cache → warm Redis and return
            logger.debug(f"Cache HIT (db fresh): {cache_key}")
            await self._warm_redis(redis_key, db_entry.data, redis_ttl)
            await self._bump_hit_count(db_entry)
            return CacheResult(
                data=json.loads(db_entry.data),
                source="db",
                is_stale=False,
            )
        
        # ──── Layer 3: Check quota threshold BEFORE calling external API ────
        quota_status = await QuotaManager.check_status(api_name)
        
        # BLOCKED (100%+): NEVER call API
        if quota_status == QuotaStatus.BLOCKED:
            logger.warning(f"Quota BLOCKED for {api_name}, serving stale cache")
            if db_entry is not None:
                return CacheResult(
                    data=json.loads(db_entry.data),
                    source="db_stale",
                    is_stale=True,
                )
            raise QuotaExhaustedError(api_name, QuotaManager.get_reset_time())
        
        # CRITICAL (90-99%): only HIGH priority gets through
        if quota_status == QuotaStatus.CRITICAL and priority != Priority.HIGH:
            logger.info(
                f"Quota CRITICAL for {api_name}, blocking {priority.value} priority"
            )
            if db_entry is not None:
                return CacheResult(
                    data=json.loads(db_entry.data),
                    source="db_stale",
                    is_stale=True,
                )
            raise QuotaNearLimitError(
                api_name, "CRITICAL",
                "Only user-initiated requests allowed at this quota level."
            )
        
        # WARNING (70-89%): block LOW priority (background/prefetch)
        if quota_status == QuotaStatus.WARNING and priority == Priority.LOW:
            logger.info(
                f"Quota WARNING for {api_name}, blocking LOW priority"
            )
            if db_entry is not None:
                return CacheResult(
                    data=json.loads(db_entry.data),
                    source="db_stale",
                    is_stale=True,
                )
            # No cache at all → allow even LOW (user should see something)
        
        # ──── Layer 3: Fetch from external API ────
        try:
            logger.info(f"Cache MISS, fetching from {api_name}: {cache_key}")
            result = await fetch_fn()
        except Exception as e:
            # API call failed → try stale cache as last resort
            logger.error(f"API call failed for {api_name}: {e}")
            if db_entry is not None:
                logger.info(f"Serving stale cache after API failure: {cache_key}")
                return CacheResult(
                    data=json.loads(db_entry.data),
                    source="db_stale",
                    is_stale=True,
                )
            raise
        
        # Record quota usage
        await QuotaManager.record_request(api_name)
        
        # ──── Store in both cache layers ────
        data_json = json.dumps(result, ensure_ascii=False, default=str)
        
        # Warm Redis
        await self._warm_redis(redis_key, data_json, redis_ttl)
        
        # Upsert into PostgreSQL
        await self._upsert_db_entry(cache_key, api_name, data_json)
        
        return CacheResult(data=result, source="api", is_stale=False)
    
    # ──── Private helpers ────
    
    async def _get_db_entry(self, cache_key: str) -> Optional[APICacheEntry]:
        """Fetch cache entry from PostgreSQL."""
        try:
            stmt = select(APICacheEntry).where(
                APICacheEntry.cache_key == cache_key
            )
            result = await self.db.execute(stmt)
            return result.scalar_one_or_none()
        except Exception as e:
            logger.error(f"DB cache read error: {e}")
            return None
    
    async def _upsert_db_entry(
        self, cache_key: str, api_name: str, data_json: str
    ) -> None:
        """Insert or update cache entry in PostgreSQL."""
        try:
            existing = await self._get_db_entry(cache_key)
            if existing is not None:
                existing.data = data_json
                existing.api_name = api_name
                existing.updated_at = datetime.now(timezone.utc)
                existing.hit_count = (existing.hit_count or 0) + 1
            else:
                entry = APICacheEntry(
                    cache_key=cache_key,
                    api_name=api_name,
                    data=data_json,
                )
                self.db.add(entry)
            await self.db.flush()
        except Exception as e:
            logger.error(f"DB cache write error for {cache_key}: {e}")
    
    async def _bump_hit_count(self, entry: APICacheEntry) -> None:
        """Increment hit counter for cache analytics."""
        try:
            entry.hit_count = (entry.hit_count or 0) + 1
            await self.db.flush()
        except Exception:
            pass  # Non-critical, don't fail on analytics
    
    async def _warm_redis(
        self, redis_key: str, data: str, ttl: int
    ) -> None:
        """Push data into Redis cache."""
        redis = await RedisClient.get_instance()
        if redis is not None:
            try:
                await redis.setex(redis_key, ttl, data)
            except Exception as e:
                logger.warning(f"Redis write error: {e}")
