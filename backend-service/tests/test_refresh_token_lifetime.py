"""A learner stays signed in for as long as they keep coming back."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.core.config import Settings, settings
from app.core.security import create_refresh_token, decode_token
from app.models.user import RefreshToken
from app.services.auth_service import save_refresh_token


def test_default_lifetime_is_months_not_a_week():
    assert Settings.model_fields["REFRESH_TOKEN_EXPIRE_DAYS"].default == 90


@pytest.mark.parametrize("days", [7, 90])
def test_the_jwt_expires_after_the_configured_days(monkeypatch, days):
    monkeypatch.setattr(settings, "REFRESH_TOKEN_EXPIRE_DAYS", days)
    payload = decode_token(create_refresh_token({"sub": str(uuid.uuid4())}))

    lifetime = datetime.fromtimestamp(payload["exp"], UTC) - datetime.now(UTC)
    assert timedelta(days=days) - timedelta(minutes=1) < lifetime <= timedelta(days=days)


@pytest.mark.asyncio
async def test_each_rotation_restarts_the_clock(db_session, monkeypatch):
    monkeypatch.setattr(settings, "REFRESH_TOKEN_EXPIRE_DAYS", 90)
    user_id, family = uuid.uuid4(), uuid.uuid4()

    await save_refresh_token(db_session, user_id, "first")
    await save_refresh_token(db_session, user_id, "second", family)

    rows = (await db_session.execute(select(RefreshToken).order_by(RefreshToken.id))).scalars().all()
    for row in rows:
        expires = row.expires_at if row.expires_at.tzinfo else row.expires_at.replace(tzinfo=UTC)
        assert timedelta(days=89, hours=23) < expires - datetime.now(UTC) <= timedelta(days=90)
