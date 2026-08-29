"""Lifecycle tests for partner API keys — audit item #7.

Covers what the static hash-list config couldn't: expiry, revocation, and
overlapping current/previous keys during rotation.
"""

import hashlib
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.partner_auth import require_partner_api_key
from app.models.partner import PartnerApiKey


def _hash(raw_key: str) -> str:
    return hashlib.sha256(raw_key.encode()).hexdigest()


async def _make_key(
    db: AsyncSession,
    raw_key: str,
    *,
    key_id: str,
    owner: str = "acme-partner",
    scope: str = "read",
    expires_at: datetime | None = None,
    revoked_at: datetime | None = None,
) -> PartnerApiKey:
    record = PartnerApiKey(
        key_id=key_id,
        key_hash=_hash(raw_key),
        owner=owner,
        scope=scope,
        expires_at=expires_at,
        revoked_at=revoked_at,
    )
    db.add(record)
    await db.commit()
    return record


@pytest.mark.asyncio
async def test_valid_key_returns_key_id_not_secret(db_session: AsyncSession):
    await _make_key(db_session, "raw-secret-value", key_id="key_abc123")

    result = await require_partner_api_key(api_key="raw-secret-value", db=db_session)

    assert result == "key_abc123"


@pytest.mark.asyncio
async def test_unknown_key_is_rejected(db_session: AsyncSession):
    with pytest.raises(HTTPException) as exc_info:
        await require_partner_api_key(api_key="never-issued", db=db_session)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_missing_key_is_rejected(db_session: AsyncSession):
    with pytest.raises(HTTPException) as exc_info:
        await require_partner_api_key(api_key=None, db=db_session)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_revoked_key_is_rejected(db_session: AsyncSession):
    await _make_key(
        db_session,
        "revoked-raw-key",
        key_id="key_revoked",
        revoked_at=datetime.now(timezone.utc) - timedelta(minutes=1),
    )

    with pytest.raises(HTTPException) as exc_info:
        await require_partner_api_key(api_key="revoked-raw-key", db=db_session)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_expired_key_is_rejected(db_session: AsyncSession):
    await _make_key(
        db_session,
        "expired-raw-key",
        key_id="key_expired",
        expires_at=datetime.now(timezone.utc) - timedelta(seconds=1),
    )

    with pytest.raises(HTTPException) as exc_info:
        await require_partner_api_key(api_key="expired-raw-key", db=db_session)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_key_expiring_in_future_is_still_accepted(db_session: AsyncSession):
    await _make_key(
        db_session,
        "not-yet-expired-key",
        key_id="key_future",
        expires_at=datetime.now(timezone.utc) + timedelta(days=1),
    )

    result = await require_partner_api_key(api_key="not-yet-expired-key", db=db_session)

    assert result == "key_future"


@pytest.mark.asyncio
async def test_rotation_old_and_new_key_both_valid_until_old_is_revoked(db_session: AsyncSession):
    """Issuing a replacement key must not require revoking the old one first —
    both rows share an owner during the rotation window."""
    await _make_key(db_session, "old-raw-key", key_id="key_old", owner="acme-partner")
    await _make_key(db_session, "new-raw-key", key_id="key_new", owner="acme-partner")

    assert await require_partner_api_key(api_key="old-raw-key", db=db_session) == "key_old"
    assert await require_partner_api_key(api_key="new-raw-key", db=db_session) == "key_new"

    # Now revoke the old key — only the new one should keep working.
    from sqlalchemy import update

    await db_session.execute(
        update(PartnerApiKey)
        .where(PartnerApiKey.key_id == "key_old")
        .values(revoked_at=datetime.now(timezone.utc))
    )
    await db_session.commit()

    with pytest.raises(HTTPException):
        await require_partner_api_key(api_key="old-raw-key", db=db_session)
    assert await require_partner_api_key(api_key="new-raw-key", db=db_session) == "key_new"
