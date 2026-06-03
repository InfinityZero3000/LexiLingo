"""Per-user quota guard for AI endpoints."""

from __future__ import annotations

import math
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
    tpm_used: int
    tpd_used: int
    tpm_limit: int
    tpd_limit: int
    backend_available: bool


class UserQuotaGuard:
    """Simple Redis-backed request quota per user and endpoint."""

    def __init__(self) -> None:
        self.rpm_limit = int(os.getenv("AI_USER_RPM_LIMIT", "30"))
        self.rpd_limit = int(os.getenv("AI_USER_RPD_LIMIT", "500"))
        self.tpm_limit = int(os.getenv("AI_USER_TPM_LIMIT", "12000"))
        self.tpd_limit = int(os.getenv("AI_USER_TPD_LIMIT", "200000"))

    async def check_and_consume(
        self,
        user_id: str,
        endpoint_key: str,
        token_cost: int = 0,
        fail_closed: bool = False,
    ) -> QuotaDecision:
        redis_client = await get_redis()
        normalized_token_cost = max(int(token_cost), 0)

        if redis_client is None:
            # Default is fail-open for resilience; sensitive endpoints can opt into fail-closed.
            return QuotaDecision(
                allowed=not fail_closed,
                rpm_used=0,
                rpd_used=0,
                rpm_limit=self.rpm_limit,
                rpd_limit=self.rpd_limit,
                tpm_used=0,
                tpd_used=0,
                tpm_limit=self.tpm_limit,
                tpd_limit=self.tpd_limit,
                backend_available=False,
            )

        now = int(time.time())
        minute_bucket = now // 60
        day_bucket = now // 86400

        rpm_key = f"ai:quota:rpm:{endpoint_key}:{user_id}:{minute_bucket}"
        rpd_key = f"ai:quota:rpd:{endpoint_key}:{user_id}:{day_bucket}"
        tpm_key = f"ai:quota:tpm:{endpoint_key}:{user_id}:{minute_bucket}"
        tpd_key = f"ai:quota:tpd:{endpoint_key}:{user_id}:{day_bucket}"

        pipeline = redis_client.pipeline()
        pipeline.incr(rpm_key)
        pipeline.expire(rpm_key, 70)
        pipeline.incr(rpd_key)
        pipeline.expire(rpd_key, 86400 + 300)
        pipeline.incrby(tpm_key, normalized_token_cost)
        pipeline.expire(tpm_key, 70)
        pipeline.incrby(tpd_key, normalized_token_cost)
        pipeline.expire(tpd_key, 86400 + 300)
        result = await pipeline.execute()

        rpm_used = int(result[0])
        rpd_used = int(result[2])
        tpm_used = int(result[4])
        tpd_used = int(result[6])
        allowed = (
            rpm_used <= self.rpm_limit
            and rpd_used <= self.rpd_limit
            and tpm_used <= self.tpm_limit
            and tpd_used <= self.tpd_limit
        )

        return QuotaDecision(
            allowed=allowed,
            rpm_used=rpm_used,
            rpd_used=rpd_used,
            rpm_limit=self.rpm_limit,
            rpd_limit=self.rpd_limit,
            tpm_used=tpm_used,
            tpd_used=tpd_used,
            tpm_limit=self.tpm_limit,
            tpd_limit=self.tpd_limit,
            backend_available=True,
        )


_guard = UserQuotaGuard()


def estimate_text_tokens(text: str) -> int:
    """Rough text token estimate for quota accounting."""
    normalized = (text or "").strip()
    if not normalized:
        return 1
    return max(1, math.ceil(len(normalized) / 4))


def default_token_cost_for_endpoint(endpoint_key: str, text: str | None = None) -> int:
    """Get endpoint-aware token reservation for per-user AI quotas."""
    base_defaults = {
        "lexi.chat": int(os.getenv("AI_TOKEN_COST_LEXI_CHAT", "1200")),
        "topic.start_session": int(os.getenv("AI_TOKEN_COST_TOPIC_START", "400")),
        "topic.send_message": int(os.getenv("AI_TOKEN_COST_TOPIC_SEND", "1000")),
        "stt.transcribe": int(os.getenv("AI_TOKEN_COST_STT", "500")),
        "tts.synthesize": int(os.getenv("AI_TOKEN_COST_TTS", "64")),
        "ai.analyze": int(os.getenv("AI_TOKEN_COST_ANALYZE", "800")),
    }
    base = base_defaults.get(endpoint_key, int(os.getenv("AI_TOKEN_COST_DEFAULT", "300")))
    if text is None:
        return max(base, 1)
    return max(base, estimate_text_tokens(text))


async def enforce_user_quota(
    user_id: str,
    endpoint_key: str,
    *,
    token_cost: int = 0,
    fail_closed: bool = False,
) -> QuotaDecision:
    decision = await _guard.check_and_consume(
        user_id=user_id,
        endpoint_key=endpoint_key,
        token_cost=token_cost,
        fail_closed=fail_closed,
    )
    if not decision.backend_available and fail_closed:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "message": "AI quota backend unavailable",
                "endpoint": endpoint_key,
            },
        )

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
                "tpm_used": decision.tpm_used,
                "tpm_limit": decision.tpm_limit,
                "tpd_used": decision.tpd_used,
                "tpd_limit": decision.tpd_limit,
            },
        )
    return decision
