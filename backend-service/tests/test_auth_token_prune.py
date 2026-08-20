"""Refresh-token rotation writes a row per refresh; the prune bounds that."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models.user import RefreshToken
from app.tasks.auth_tokens import SPENT_TOKEN_GRACE, prune_refresh_tokens


def _token(**overrides) -> RefreshToken:
    now = datetime.now(UTC)
    defaults = dict(
        user_id=uuid.uuid4(),
        token=f"token-{uuid.uuid4()}",
        is_revoked=False,
        is_used=False,
        expires_at=now + timedelta(days=7),
        created_at=now,
    )
    return RefreshToken(**{**defaults, **overrides})


@pytest.mark.asyncio
async def test_prune_removes_only_unusable_tokens(db_session):
    now = datetime.now(UTC)

    live = _token()
    just_spent = _token(is_used=True, created_at=now)
    expired = _token(expires_at=now - timedelta(minutes=1))
    long_spent = _token(is_used=True, created_at=now - SPENT_TOKEN_GRACE - timedelta(hours=1))
    long_revoked = _token(
        is_revoked=True, created_at=now - SPENT_TOKEN_GRACE - timedelta(hours=1)
    )

    db_session.add_all([live, just_spent, expired, long_spent, long_revoked])
    await db_session.commit()

    deleted = await prune_refresh_tokens(db_session, now=now)
    assert deleted == 3

    remaining = (await db_session.execute(select(RefreshToken.token))).scalars().all()
    assert set(remaining) == {live.token, just_spent.token}
