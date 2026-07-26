"""Authentication for read-only partner integration APIs."""

import hashlib
import hmac

from fastapi import HTTPException, Security, status
from fastapi.security import APIKeyHeader

from app.core.config import settings


_partner_key_header = APIKeyHeader(
    name="X-LexiLingo-API-Key",
    auto_error=False,
)


async def require_partner_api_key(
    api_key: str | None = Security(_partner_key_header),
) -> str:
    configured_hashes = [
        value.strip().lower()
        for value in settings.LEXILINGO_PARTNER_API_KEY_HASHES.split(",")
        if value.strip()
    ]
    candidate_hash = hashlib.sha256((api_key or "").encode()).hexdigest()
    if not api_key or not any(
        hmac.compare_digest(candidate_hash, expected)
        for expected in configured_hashes
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid partner API key",
        )
    return candidate_hash[:12]
