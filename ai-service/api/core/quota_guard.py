"""Per-user quota guard for AI endpoints."""

from __future__ import annotations

import os
import time
from dataclasses import dataclass

from fastapi import HTTPException, status

from api.core.redis_client import get_redis


@dataclass
class QuotaDecision:
    allowed: bool
    rpm_used: int
    rpd_used: int
    rpm_limit: int
    rpd_limit: int


class UserQuotaGuard:
    """Simple Redis-backed request quota per user and endpoint."""

    def __init__(self) -> None:
        self.rpm_limit = int(os.getenv("AI_USER_RPM_LIMIT", "30"))
        self.rpd_limit = int(os.getenv("AI_USER_RPD_LIMIT", "500"))

    async def check_and_consume(self, user_id: str, endpoint_key: str) -> QuotaDecision:
        redis_client = await get_redis()
        if redis_client is None:
            # Fail-open when Redis is unavailable to keep service alive.
            return QuotaDecision(
                allowed=True,
                rpm_used=0,
                rpd_used=0,
                rpm_limit=self.rpm_limit,
                rpd_limit=self.rpd_limit,
            )

        now = int(time.time())
        minute_bucket = now // 60
        day_bucket = now // 86400

        rpm_key = f"ai:quota:rpm:{endpoint_key}:{user_id}:{minute_bucket}"
        rpd_key = f"ai:quota:rpd:{endpoint_key}:{user_id}:{day_bucket}"

        pipeline = redis_client.pipeline()
        pipeline.incr(rpm_key)
        pipeline.expire(rpm_key, 70)
        pipeline.incr(rpd_key)
        pipeline.expire(rpd_key, 86400 + 300)
        result = await pipeline.execute()

        rpm_used = int(result[0])
        rpd_used = int(result[2])
        allowed = rpm_used <= self.rpm_limit and rpd_used <= self.rpd_limit

        return QuotaDecision(
            allowed=allowed,
            rpm_used=rpm_used,
            rpd_used=rpd_used,
            rpm_limit=self.rpm_limit,
            rpd_limit=self.rpd_limit,
        )


_guard = UserQuotaGuard()


async def enforce_user_quota(user_id: str, endpoint_key: str) -> QuotaDecision:
    decision = await _guard.check_and_consume(user_id=user_id, endpoint_key=endpoint_key)
    if not decision.allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "message": "AI request quota exceeded",
                "endpoint": endpoint_key,
                "rpm_used": decision.rpm_used,
                "rpm_limit": decision.rpm_limit,
                "rpd_used": decision.rpd_used,
                "rpd_limit": decision.rpd_limit,
            },
        )
    return decision
