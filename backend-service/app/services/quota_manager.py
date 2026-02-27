"""
Quota Manager — Graduated Near-Limit Threshold System

Tracks API usage against daily budgets using Redis counters.
Implements 4-level threshold: NORMAL → WARNING → CRITICAL → BLOCKED.
Quotas auto-reset daily via date-keyed Redis entries.

Phase 0 Infrastructure: Required by all content features.
"""

import logging
from datetime import date, datetime, timedelta
from enum import Enum
from typing import Optional

from app.core.redis import RedisClient

logger = logging.getLogger(__name__)


class QuotaStatus(Enum):
    """Graduated quota threshold levels."""
    NORMAL = "normal"       # 0-69%   → all requests allowed
    WARNING = "warning"     # 70-89%  → block LOW priority
    CRITICAL = "critical"   # 90-99%  → only HIGH priority
    BLOCKED = "blocked"     # 100%+   → all requests blocked


class Priority(Enum):
    """Request priority levels for quota-aware routing."""
    HIGH = "high"       # User-initiated: search, tap-to-read, explicit action
    MEDIUM = "medium"   # Auto-load: screen open, scroll pagination
    LOW = "low"         # Background: prefetch, related content, cron jobs


class QuotaManager:
    """
    Track API usage with graduated near-limit thresholds.
    
    Budget = internal limit (lower than actual API limit for safety buffer).
    Thresholds are based on budget, not the actual API limit.
    
    Usage:
        quota_mgr = QuotaManager()
        status = await quota_mgr.check_status("newsapi", cost=1)
        if status != QuotaStatus.BLOCKED:
            # make API call
            await quota_mgr.record_request("newsapi", cost=1)
    """
    
    # Internal budget per API (20% buffer below actual free tier limit)
    LIMITS: dict[str, int] = {
        "newsapi": 80,          # actual: 100 req/day
        "newsdata": 160,        # actual: 200 req/day
        "youtube": 8000,        # actual: 10,000 units/day
        "podcastindex": 500,    # actual: unlimited (self-imposed respectful limit)
        "openlibrary": 1000,    # actual: unlimited
        "gutenberg": 200,       # actual: unlimited
        "dictionary": 2000,     # actual: unlimited
        "wordsapi": 2000,       # actual: 2,500 req/day
        "rss_feed": 500,        # RSS feeds are free — self-imposed limit
    }
    
    # Threshold percentages
    WARNING_THRESHOLD: float = 0.70     # 70% of budget
    CRITICAL_THRESHOLD: float = 0.90    # 90% of budget
    
    @classmethod
    def _redis_key(cls, api_name: str) -> str:
        """Generate date-keyed Redis key (auto-resets daily)."""
        return f"quota:{api_name}:{date.today().isoformat()}"
    
    @classmethod
    async def check_status(cls, api_name: str, cost: int = 1) -> QuotaStatus:
        """
        Check current quota status with graduated thresholds.
        
        Args:
            api_name: API identifier (must exist in LIMITS)
            cost: Cost of the upcoming request (units)
            
        Returns:
            QuotaStatus enum value
        """
        redis = await RedisClient.get_instance()
        if redis is None:
            # Redis down → be conservative, allow but log
            logger.warning(f"Redis unavailable, assuming NORMAL for {api_name}")
            return QuotaStatus.NORMAL
        
        budget = cls.LIMITS.get(api_name)
        if budget is None:
            logger.error(f"Unknown API: {api_name}. No quota limit configured.")
            return QuotaStatus.NORMAL
        
        key = cls._redis_key(api_name)
        current = int(await redis.get(key) or 0)
        usage_ratio = (current + cost) / budget
        
        if usage_ratio >= 1.0:
            return QuotaStatus.BLOCKED
        elif usage_ratio >= cls.CRITICAL_THRESHOLD:
            return QuotaStatus.CRITICAL
        elif usage_ratio >= cls.WARNING_THRESHOLD:
            return QuotaStatus.WARNING
        return QuotaStatus.NORMAL
    
    @classmethod
    async def can_proceed(
        cls, api_name: str, priority: Priority, cost: int = 1
    ) -> bool:
        """
        Check if a request with given priority can proceed.
        
        Rules:
            NORMAL   → all priorities allowed
            WARNING  → block LOW
            CRITICAL → block LOW + MEDIUM (only HIGH allowed)
            BLOCKED  → block ALL
        """
        status = await cls.check_status(api_name, cost)
        
        if status == QuotaStatus.BLOCKED:
            return False
        if status == QuotaStatus.CRITICAL and priority != Priority.HIGH:
            return False
        if status == QuotaStatus.WARNING and priority == Priority.LOW:
            return False
        return True
    
    @classmethod
    async def record_request(cls, api_name: str, cost: int = 1) -> QuotaStatus:
        """
        Record an API request and return updated status.
        Auto-logs warnings when thresholds are crossed.
        
        Args:
            api_name: API identifier
            cost: Cost of the request (1 for normal, 100 for YouTube search.list)
            
        Returns:
            Updated QuotaStatus after recording
        """
        redis = await RedisClient.get_instance()
        if redis is None:
            logger.warning(f"Redis unavailable, cannot track quota for {api_name}")
            return QuotaStatus.NORMAL
        
        key = cls._redis_key(api_name)
        new_count = await redis.incrby(key, cost)
        await redis.expire(key, 86400)  # Auto-expire after 24h (cleanup)
        
        budget = cls.LIMITS.get(api_name, 1)
        ratio = new_count / budget
        
        # Log threshold crossings
        if ratio >= 1.0:
            logger.warning(
                f"🚫 BLOCKED: {api_name} at {ratio*100:.0f}% "
                f"({new_count}/{budget}). No more requests until reset."
            )
        elif ratio >= cls.CRITICAL_THRESHOLD:
            logger.warning(
                f"🔴 CRITICAL: {api_name} at {ratio*100:.0f}% "
                f"({new_count}/{budget}). Only HIGH priority allowed."
            )
        elif ratio >= cls.WARNING_THRESHOLD:
            logger.info(
                f"⚠️ WARNING: {api_name} at {ratio*100:.0f}% "
                f"({new_count}/{budget}). LOW priority blocked."
            )
        
        return await cls.check_status(api_name, cost=0)
    
    @classmethod
    async def get_usage(cls, api_name: str) -> dict:
        """Get detailed usage info including threshold status."""
        redis = await RedisClient.get_instance()
        used = 0
        if redis is not None:
            key = cls._redis_key(api_name)
            used = int(await redis.get(key) or 0)
        
        budget = cls.LIMITS.get(api_name, 0)
        status = await cls.check_status(api_name, cost=0)
        
        return {
            "api": api_name,
            "used": used,
            "budget": budget,
            "remaining": max(0, budget - used),
            "usage_percent": round(used / budget * 100, 1) if budget else 0,
            "status": status.value,
            "warning_at": int(budget * cls.WARNING_THRESHOLD),
            "critical_at": int(budget * cls.CRITICAL_THRESHOLD),
            "resets_in": cls.get_reset_time(),
        }
    
    @classmethod
    async def get_all_usage(cls) -> list[dict]:
        """Get usage for all configured APIs (e.g., for admin dashboard)."""
        return [await cls.get_usage(api) for api in cls.LIMITS]
    
    @classmethod
    def get_reset_time(cls) -> str:
        """Return human-readable time until daily quota resets (midnight UTC)."""
        now = datetime.utcnow()
        reset = (now + timedelta(days=1)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        remaining = reset - now
        hours = remaining.seconds // 3600
        minutes = (remaining.seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    
    @classmethod
    async def reset_quota(cls, api_name: str) -> bool:
        """Manual quota reset (emergency use / admin endpoint)."""
        redis = await RedisClient.get_instance()
        if redis is None:
            return False
        
        key = cls._redis_key(api_name)
        await redis.delete(key)
        logger.info(f"🔄 Manual quota reset for {api_name}")
        return True
