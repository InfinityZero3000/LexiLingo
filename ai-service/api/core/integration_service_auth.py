"""Authentication for external service integrations."""

from __future__ import annotations

import hashlib
import hmac
from datetime import datetime, timezone

from fastapi import HTTPException, Security, status
from fastapi.security import APIKeyHeader

from api.core.config import get_settings


_token_header = APIKeyHeader(name="X-LexiLingo-Service-Token", auto_error=False)


async def verify_trace_cag_service_token(
    token: str | None = Security(_token_header),
) -> str:
    settings = get_settings()
    if not settings.TRACE_CAG_EXTERNAL_ENABLED:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "TraceCAG integration is disabled")
    current = settings.TRACE_CAG_SERVICE_TOKEN_HASH.strip().lower()
    if not current:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "TraceCAG integration is not configured")

    candidate = hashlib.sha256((token or "").encode()).hexdigest()
    accepted = hmac.compare_digest(candidate, current)
    previous = settings.TRACE_CAG_PREVIOUS_TOKEN_HASH.strip().lower()
    if previous and _previous_token_active(settings.TRACE_CAG_PREVIOUS_TOKEN_VALID_UNTIL):
        accepted = hmac.compare_digest(candidate, previous) or accepted
    if not accepted:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid service token")
    return token or ""


def _previous_token_active(raw: str) -> bool:
    try:
        expires = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return False
    return expires.astimezone(timezone.utc) > datetime.now(timezone.utc)
