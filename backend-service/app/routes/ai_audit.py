"""AI audit ingestion routes.

These endpoints allow ai-service to push interaction audit events to backend-service.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, status

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.core.redis import get_redis
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ai-audit", tags=["AI Audit"])


def _check_ingest_secret(x_ai_service_secret: str | None) -> None:
    expected = settings.AI_AUDIT_INGEST_SECRET
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI audit ingest secret is not configured",
        )
    if not x_ai_service_secret or x_ai_service_secret != expected:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid AI service ingest secret",
        )


@router.post("/events")
async def ingest_ai_audit_event(
    payload: dict[str, Any],
    x_ai_service_secret: str | None = Header(default=None, alias="X-AI-Service-Secret"),
):
    """Ingest a single AI audit event from ai-service."""
    _check_ingest_secret(x_ai_service_secret)

    user_id = str(payload.get("user_id") or "unknown")
    event = {
        **payload,
        "received_at": datetime.now(timezone.utc).isoformat(),
    }

    redis_client = await get_redis()
    if redis_client is not None:
        key_user = f"ai:audit:user:{user_id}"
        key_global = "ai:audit:all"
        packed = json.dumps(event, ensure_ascii=True)
        # Keep a capped rolling history to avoid unbounded memory growth.
        await redis_client.lpush(key_user, packed)
        await redis_client.ltrim(key_user, 0, 299)
        await redis_client.expire(key_user, 14 * 24 * 3600)

        await redis_client.lpush(key_global, packed)
        await redis_client.ltrim(key_global, 0, 2999)
        await redis_client.expire(key_global, 14 * 24 * 3600)

    logger.info(
        "AI audit event ingested user_id=%s endpoint=%s status=%s request_id=%s",
        user_id,
        event.get("endpoint"),
        event.get("status"),
        event.get("request_id"),
    )

    return {"success": True}


@router.get("/events/me")
async def list_my_ai_audit_events(
    limit: int = 50,
    current_user: User = Depends(get_current_user),
):
    """Get latest AI audit events for the current authenticated user."""
    safe_limit = min(max(limit, 1), 200)

    redis_client = await get_redis()
    if redis_client is None:
        return {"events": [], "total": 0}

    key_user = f"ai:audit:user:{str(current_user.id)}"
    rows = await redis_client.lrange(key_user, 0, safe_limit - 1)

    events: list[dict[str, Any]] = []
    for row in rows:
        try:
            events.append(json.loads(row))
        except Exception:
            continue

    return {"events": events, "total": len(events)}
