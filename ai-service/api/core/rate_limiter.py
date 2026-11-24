"""
Redis-backed sliding window rate limiter for multi-worker safety.
"""

import time
import logging
from typing import Optional, Tuple

import redis.asyncio as redis

logger = logging.getLogger(__name__)


def _sum_token_members(members) -> int:
    total = 0
    for raw in members:
        value = raw.decode() if isinstance(raw, bytes) else str(raw)
        try:
            total += int(value.rsplit("-", 3)[1])
        except (IndexError, ValueError):
            logger.warning("Ignoring malformed TPM limiter member")
    return total

def voice_rpm_cap(rpm_limit: int, safety: float) -> int:
    """Voice requests one key admits per minute; the Lua admission and the admin view share it."""
    return max(1, int(rpm_limit * safety))


class RedisRateLimiter:
    """
    Sliding-window rate limiter using Redis for multi-worker consistency.
    """
    def __init__(
        self, 
        redis_client: redis.Redis, 
        prefix: str, 
        rpm_limit: int, 
        tpm_limit: int, 
        rpd_limit: int,
        safety: float = 0.90
    ):
        self.redis = redis_client
        self.prefix = prefix
        self.rpm_limit = rpm_limit
        self.tpm_limit = tpm_limit
        self.rpd_limit = rpd_limit
        self.safety = safety

    def blocked_by(self, rpm: int, tpm: int, rpd: int, estimated_tokens: int = 0) -> Optional[str]:
        """The window that refuses a request of this size, or None; the one admission rule."""
        if rpd >= self.rpd_limit * self.safety:
            return "rpd"
        if rpm >= self.rpm_limit * self.safety:
            return "rpm"
        if tpm + estimated_tokens >= self.tpm_limit * self.safety:
            return "tpm"
        return None

    async def window_counts(self) -> Tuple[int, int, int]:
        """Requests and tokens used in the current minute, and requests in the current day."""
        now = time.time()
        minute_ago = now - 60
        day_ago = now - 86400
        rpm_key = f"{self.prefix}:rpm"
        tpm_key = f"{self.prefix}:tpm"
        rpd_key = f"{self.prefix}:rpd"

        async with self.redis.pipeline() as pipe:
            pipe.zremrangebyscore(rpm_key, 0, minute_ago)
            pipe.zremrangebyscore(tpm_key, 0, minute_ago)
            pipe.zremrangebyscore(rpd_key, 0, day_ago)
            await pipe.execute()

        async with self.redis.pipeline() as pipe:
            pipe.zcard(rpm_key)
            pipe.zrange(tpm_key, 0, -1)
            pipe.zcard(rpd_key)
            results = await pipe.execute()
        return results[0], _sum_token_members(results[1]), results[2]

    async def voice_state(self) -> Tuple[int, bool]:
        """Voice requests in the current minute and whether a voice lease is held."""
        async with self.redis.pipeline(transaction=False) as pipe:
            pipe.zcount(f"{self.prefix}:voice:rpm", time.time() - 60, "+inf")
            pipe.exists(f"{self.prefix}:voice:lease")
            count, lease = await pipe.execute()
        return count, bool(lease)

    async def can_request(self, estimated_tokens: int = 600) -> bool:
        """Check if request is within limits."""
        try:
            rpm_count, tpm_count, rpd_count = await self.window_counts()
            blocked = self.blocked_by(rpm_count, tpm_count, rpd_count, estimated_tokens)
            if blocked:
                used, limit = {"rpm": (rpm_count, self.rpm_limit), "tpm": (tpm_count, self.tpm_limit),
                               "rpd": (rpd_count, self.rpd_limit)}[blocked]
                logger.warning(f"RateLimit ({self.prefix}) {blocked.upper()} near limit: {used}/{limit}")
            return blocked is None
        except Exception as e:
            logger.error(f"Rate limiter error: {e}")
            return True # Fallback to allowing request on Redis failure

    async def record(self, tokens_used: int):
        """Record usage."""
        now = time.time()
        rpm_key = f"{self.prefix}:rpm"
        tpm_key = f"{self.prefix}:tpm"
        rpd_key = f"{self.prefix}:rpd"

        try:
            async with self.redis.pipeline() as pipe:
                # Use a unique identifier for the set member to allow multiple requests at the same timestamp
                member = f"{now}-{tokens_used}-{time.time_ns()}"
                pipe.zadd(rpm_key, {member: now})
                pipe.zadd(tpm_key, {f"{now}-{tokens_used}-{time.time_ns()}-tokens": now})
                pipe.zadd(rpd_key, {member: now})
                # Set TTL
                pipe.expire(rpm_key, 65)
                pipe.expire(tpm_key, 65)
                pipe.expire(rpd_key, 86500)
                await pipe.execute()
        except Exception as e:
            logger.error(f"Failed to record usage in rate limiter: {e}")
