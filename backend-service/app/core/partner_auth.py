"""Authentication for read-only partner integration APIs."""

import hashlib
import logging
from datetime import datetime, timezone

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.partner import PartnerApiKey

logger = logging.getLogger(__name__)

_partner_key_header = APIKeyHeader(
    name="X-LexiLingo-API-Key",
    auto_error=False,
)

_UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Invalid partner API key",
)


async def require_partner_api_key(
    api_key: str | None = Security(_partner_key_header),
    db: AsyncSession = Depends(get_db),
) -> str:
    """Validate a partner API key against `partner_api_keys` and return its
    key_id (never the raw key or hash — safe to log/attach to request state).
    Multiple non-revoked, non-expired rows may share an owner, so issuing a
    new key and revoking the old one can overlap during rotation."""
    if not api_key:
        raise _UNAUTHORIZED

    candidate_hash = hashlib.sha256(api_key.encode()).hexdigest()
    result = await db.execute(
        select(PartnerApiKey).where(PartnerApiKey.key_hash == candidate_hash)
    )
    record = result.scalar_one_or_none()

    now = datetime.now(timezone.utc)
    if (
        record is None
        or record.revoked_at is not None
        or (record.expires_at is not None and record.expires_at <= now)
    ):
        logger.warning(
            "Partner API key rejected: key_id=%s", record.key_id if record else "unknown"
        )
        raise _UNAUTHORIZED

    return record.key_id
