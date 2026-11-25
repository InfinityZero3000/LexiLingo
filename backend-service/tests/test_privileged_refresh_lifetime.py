"""Admin sessions live shorter than learner sessions (real Postgres)."""

from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.config import settings
from app.core.database import get_db
from app.core.security import create_refresh_token, decode_token, hash_refresh_token
from app.main import app
from app.models.user import RefreshToken
from app.services.auth_service import issue_refresh_token, refresh_lifetime_days, save_refresh_token

BASE = "/api/v1/auth"


@pytest.fixture
async def client(db_engine, test_user, admin_user):
    factory = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)

    async def per_request_db():
        async with factory() as session:
            yield session

    app.dependency_overrides[get_db] = per_request_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def windows(monkeypatch):
    monkeypatch.setattr(settings, "REFRESH_TOKEN_EXPIRE_DAYS", 90)
    monkeypatch.setattr(settings, "REFRESH_TOKEN_EXPIRE_DAYS_PRIVILEGED", 7)


def _aware(moment: datetime) -> datetime:
    return moment if moment.tzinfo else moment.replace(tzinfo=UTC)


def _days_from_now(moment: datetime) -> float:
    return (_aware(moment) - datetime.now(UTC)).total_seconds() / 86400


async def _row(db_session, token: str) -> RefreshToken:
    db_session.expire_all()
    query = select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(token))
    return (await db_session.execute(query)).scalar_one()


async def _issue_long_token_issued_days_ago(db_session, user, days_ago: float) -> str:
    """A token issued under the learner window, as a promoted account would still hold."""
    token = create_refresh_token({"sub": str(user.id)}, expires_days=90)
    await save_refresh_token(db_session, user.id, token, lifetime_days=90)
    row = await _row(db_session, token)
    row.created_at = datetime.now(UTC) - timedelta(days=days_ago)
    await db_session.commit()
    return token


@pytest.mark.asyncio
async def test_admin_tokens_get_the_short_window_and_learners_the_long_one(
    db_session, test_user, admin_user
):
    learner = await issue_refresh_token(db_session, test_user.id)
    admin = await issue_refresh_token(db_session, admin_user.id)

    for token, days in ((learner, 90), (admin, 7)):
        assert days - 1 < _days_from_now((await _row(db_session, token)).expires_at) <= days
        # The JWT is what the client carries; it must say the same as the row.
        expires = datetime.fromtimestamp(decode_token(token)["exp"], UTC)
        assert abs(_days_from_now(expires) - days) < 0.01


@pytest.mark.asyncio
async def test_the_privileged_window_can_be_tuned_but_never_exceeds_the_base(
    db_session, admin_user, monkeypatch
):
    monkeypatch.setattr(settings, "REFRESH_TOKEN_EXPIRE_DAYS_PRIVILEGED", 30)
    assert await refresh_lifetime_days(db_session, admin_user.id) == 30

    monkeypatch.setattr(settings, "REFRESH_TOKEN_EXPIRE_DAYS_PRIVILEGED", 365)
    assert await refresh_lifetime_days(db_session, admin_user.id) == 90


@pytest.mark.asyncio
async def test_rotation_keeps_each_roles_window(client, db_session, test_user, admin_user):
    # Ids first: _row() expires the session, and a loaded user cannot refresh itself outside a greenlet.
    for user_id, days in ((test_user.id, 90), (admin_user.id, 7)):
        first = await issue_refresh_token(db_session, user_id)
        response = await client.post(f"{BASE}/refresh", json={"refresh_token": first})
        assert response.status_code == 200

        second = response.json()["refresh_token"]
        assert days - 1 < _days_from_now((await _row(db_session, second)).expires_at) <= days
        expires = datetime.fromtimestamp(decode_token(second)["exp"], UTC)
        assert abs(_days_from_now(expires) - days) < 0.01


@pytest.mark.asyncio
async def test_an_admin_cannot_use_a_long_token_older_than_the_admin_window(
    client, db_session, admin_user
):
    token = await _issue_long_token_issued_days_ago(db_session, admin_user, days_ago=8)

    response = await client.post(f"{BASE}/refresh", json={"refresh_token": token})

    assert response.status_code == 401
    assert (await _row(db_session, token)).is_used is False  # refused, not spent


@pytest.mark.asyncio
async def test_an_admin_within_the_window_refreshes_and_lands_on_the_short_one(
    client, db_session, admin_user
):
    token = await _issue_long_token_issued_days_ago(db_session, admin_user, days_ago=6)

    response = await client.post(f"{BASE}/refresh", json={"refresh_token": token})

    assert response.status_code == 200
    renewed = await _row(db_session, response.json()["refresh_token"])
    assert 6 < _days_from_now(renewed.expires_at) <= 7


@pytest.mark.asyncio
async def test_a_learner_with_the_same_old_token_is_unaffected(client, db_session, test_user):
    token = await _issue_long_token_issued_days_ago(db_session, test_user, days_ago=8)

    response = await client.post(f"{BASE}/refresh", json={"refresh_token": token})

    assert response.status_code == 200
