"""
API Cache Service — 3-Layer Cache with Quota-Aware Fetching

Layer 1: Redis (hot cache, short TTL)
Layer 2: PostgreSQL (persistent cache, longer TTL)
Layer 3: External API (actual HTTP call)

Before hitting Layer 3, checks QuotaManager thresholds.
Serves stale data when quota is exhausted rather than failing.

Phase 0 Infrastructure: Required by all content features.
"""

import asyncio
import json
import logging
import uuid
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
    
    # ponytail: bounded lease, not a full distributed lock — if the holder
    # crashes the lease just expires after LEASE_TTL_SECONDS and the next
    # caller re-fetches; upgrade to a renewing lock if fetches start
    # exceeding this window.
    LEASE_TTL_SECONDS = 30
    LEASE_WAIT_ATTEMPTS = 8
    LEASE_WAIT_INTERVAL_SECONDS = 0.5

    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def get_or_fetch(
        self,
        cache_key: str,
        api_name: str,
        fetch_fn: Callable,
        priority: Priority = Priority.MEDIUM,
        cost: int = 1,
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
            cost: Quota units consumed by a cache miss; 0 bypasses quota checks
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
        
        if cost > 0:
            # ──── Layer 3: Check quota threshold BEFORE calling external API ────
            quota_status = await QuotaManager.check_status(api_name, cost=cost)

            # BLOCKED (100%+): NEVER call API
            if quota_status == QuotaStatus.BLOCKED:
                logger.warning("Quota BLOCKED for %s, serving stale cache", api_name)
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
                    "Quota CRITICAL for %s, blocking %s priority",
                    api_name,
                    priority.value,
                )
                if db_entry is not None:
                    return CacheResult(
                        data=json.loads(db_entry.data),
                        source="db_stale",
                        is_stale=True,
                    )
                raise QuotaNearLimitError(
                    api_name,
                    "CRITICAL",
                    "Only user-initiated requests allowed at this quota level.",
                )

            # WARNING (70-89%): block LOW priority (background/prefetch)
            if quota_status == QuotaStatus.WARNING and priority == Priority.LOW:
                logger.info("Quota WARNING for %s, blocking LOW priority", api_name)
                if db_entry is not None:
                    return CacheResult(
                        data=json.loads(db_entry.data),
                        source="db_stale",
                        is_stale=True,
                    )
                # No cache at all → allow even LOW (user should see something)
        
        # ──── Layer 3: Fetch from external API ────
        # Acquire a short lease so concurrent requests/replicas for the same
        # cache_key don't all call the upstream API at once. If another
        # request holds the lease, poll the cache briefly for its result
        # instead of fetching ourselves.
        lease_key = f"api-lease:{cache_key}"
        lease_token = uuid.uuid4().hex
        have_lease = await self._acquire_lease(lease_key, lease_token)

        if not have_lease:
            # Poll for the holder's result for up to the lease's own TTL,
            # periodically retrying to acquire it ourselves. A short,
            # fixed wait budget here (independent of LEASE_TTL_SECONDS)
            # would make every waiter give up and stampede the upstream
            # API in lock-step whenever a fetch legitimately runs longer
            # than that budget — exactly the pattern the lease exists to
            # prevent.
            max_attempts = max(1, int(self.LEASE_TTL_SECONDS / self.LEASE_WAIT_INTERVAL_SECONDS))
            for _ in range(max_attempts):
                waited = await self._wait_for_lease_result(redis_key, cache_key, attempts=1)
                if waited is not None:
                    return waited
                have_lease = await self._acquire_lease(lease_key, lease_token)
                if have_lease:
                    break
            # Lease holder never populated the cache and the lease window
            # fully elapsed without us acquiring it (Redis unavailable, or
            # a holder that keeps renewing) — fall through and fetch
            # anyway rather than hang the request indefinitely.

        try:
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

            # Record quota usage only for calls that consume upstream quota.
            if cost > 0:
                await QuotaManager.record_request(api_name, cost=cost)

            # ──── Store in both cache layers ────
            data_json = json.dumps(result, ensure_ascii=False, default=str)

            # Warm Redis
            await self._warm_redis(redis_key, data_json, redis_ttl)

            # Upsert into PostgreSQL
            await self._upsert_db_entry(cache_key, api_name, data_json)

            return CacheResult(data=result, source="api", is_stale=False)
        finally:
            if have_lease:
                await self._release_lease(lease_key, lease_token)
    
    # ──── Private helpers ────

    async def _acquire_lease(self, lease_key: str, token: str) -> bool:
        """Try to claim the fetch lease. False if Redis is down or another
        caller already holds it — never blocks the caller from proceeding."""
        redis = await RedisClient.get_instance()
        if redis is None:
            return False
        try:
            return bool(
                await redis.set(lease_key, token, nx=True, px=self.LEASE_TTL_SECONDS * 1000)
            )
        except Exception as e:
            logger.warning(f"Redis lease acquire error for {lease_key}: {e}")
            return False

    # Compare-and-delete must be atomic: a separate GET-then-DEL can delete
    # a *different* caller's lease if ours expired and was reclaimed in the
    # gap between the two round trips.
    _RELEASE_SCRIPT = (
        "if redis.call('get', KEYS[1]) == ARGV[1] then "
        "return redis.call('del', KEYS[1]) "
        "else return 0 end"
    )

    async def _release_lease(self, lease_key: str, token: str) -> None:
        """Release the lease only if we still hold it (token match)."""
        redis = await RedisClient.get_instance()
        if redis is None:
            return
        try:
            await redis.eval(self._RELEASE_SCRIPT, 1, lease_key, token)
        except Exception as e:
            logger.warning(f"Redis lease release error for {lease_key}: {e}")

    async def _wait_for_lease_result(
        self, redis_key: str, cache_key: str, attempts: int | None = None
    ) -> Optional[CacheResult]:
        """Poll Redis briefly for a result populated by the lease holder."""
        redis = await RedisClient.get_instance()
        if redis is None:
            return None
        for _ in range(self.LEASE_WAIT_ATTEMPTS if attempts is None else attempts):
            await asyncio.sleep(self.LEASE_WAIT_INTERVAL_SECONDS)
            try:
                cached = await redis.get(redis_key)
            except Exception as e:
                logger.warning(f"Redis read error while waiting on lease for {cache_key}: {e}")
                return None
            if cached is not None:
                logger.debug(f"Cache HIT (redis, after lease wait): {cache_key}")
                return CacheResult(data=json.loads(cached), source="redis", is_stale=False)
        return None

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
            async with self.db.begin_nested():
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
            async with self.db.begin_nested():
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
