"""
Redis-backed sliding window rate limiter for multi-worker safety.
"""

import time
import logging
import redis.asyncio as redis
from typing import Optional

logger = logging.getLogger(__name__)

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

    async def can_request(self, estimated_tokens: int = 600) -> bool:
        """Check if request is within limits."""
        now = time.time()
        minute_ago = now - 60
        day_ago = now - 86400

        # Keys
        rpm_key = f"{self.prefix}:rpm"
        tpm_key = f"{self.prefix}:tpm"
        rpd_key = f"{self.prefix}:rpd"

        try:
            # Clean old entries
            async with self.redis.pipeline() as pipe:
                pipe.zremrangebyscore(rpm_key, 0, minute_ago)
                pipe.zremrangebyscore(tpm_key, 0, minute_ago)
                pipe.zremrangebyscore(rpd_key, 0, day_ago)
                await pipe.execute()

            # Get counts
            async with self.redis.pipeline() as pipe:
                pipe.zcard(rpm_key)
                pipe.zrange(tpm_key, 0, -1, withscores=True)
                pipe.zcard(rpd_key)
                results = await pipe.execute()

            rpm_count = results[0]
            tpm_count = sum(float(tokens) for _, tokens in results[1])
            rpd_count = results[2]

            if rpm_count >= self.rpm_limit * self.safety:
                logger.warning(f"RateLimit ({self.prefix}) RPM near limit: {rpm_count}/{self.rpm_limit}")
                return False
            
            if tpm_count + estimated_tokens >= self.tpm_limit * self.safety:
                logger.warning(f"RateLimit ({self.prefix}) TPM near limit: {tpm_count}/{self.tpm_limit}")
                return False

            if rpd_count >= self.rpd_limit * self.safety:
                logger.warning(f"RateLimit ({self.prefix}) RPD near limit: {rpd_count}/{self.rpd_limit}")
                return False

            return True

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
                member = f"{now}-{tokens_used}"
                pipe.zadd(rpm_key, {member: now})
                pipe.zadd(tpm_key, {f"{now}-{tokens_used}-tokens": tokens_used}, score=now)
                pipe.zadd(rpd_key, {member: now})
                # Set TTL
                pipe.expire(rpm_key, 65)
                pipe.expire(tpm_key, 65)
                pipe.expire(rpd_key, 86500)
                await pipe.execute()
        except Exception as e:
            logger.error(f"Failed to record usage in rate limiter: {e}")
