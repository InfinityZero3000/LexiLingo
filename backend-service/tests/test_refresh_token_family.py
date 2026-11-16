"""Refresh tokens are stored hashed and rotate as a family (real Postgres)."""

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.database import get_db
from app.core.config import settings
from app.core.security import create_refresh_token, hash_refresh_token
from app.main import app
from app.models.user import RefreshToken
from app.services.auth_service import save_refresh_token

BASE = "/api/v1/auth"


@pytest.fixture
async def client(db_engine, test_user):
    """Every request gets its own session, as in production, so locks really contend."""
    factory = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)

    async def per_request_db():
        async with factory() as session:
            yield session

    app.dependency_overrides[get_db] = per_request_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


async def _issue(db_session, user, family_id=None) -> str:
    token = create_refresh_token({"sub": str(user.id)})
    await save_refresh_token(db_session, user.id, token, family_id)
    return token


async def _rows(db_session) -> list[RefreshToken]:
    db_session.expire_all()
    return list((await db_session.execute(select(RefreshToken))).scalars())


@pytest.mark.asyncio
async def test_token_is_stored_as_hash_not_raw(db_session, test_user):
    token = await _issue(db_session, test_user)
    (row,) = await _rows(db_session)
    assert row.token_hash == hash_refresh_token(token)
    assert row.token is None
    assert row.family_id is not None


@pytest.mark.asyncio
async def test_rotation_keeps_family_and_spends_old_token(client, db_session, test_user):
    first = await _issue(db_session, test_user)
    r = await client.post(f"{BASE}/refresh", json={"refresh_token": first})
    assert r.status_code == 200
    second = r.json()["refresh_token"]
    assert second != first

    rows = {row.token_hash: row for row in await _rows(db_session)}
    old, new = rows[hash_refresh_token(first)], rows[hash_refresh_token(second)]
    assert old.is_used and not old.is_revoked
    assert not new.is_used and new.family_id == old.family_id

    again = await client.post(f"{BASE}/refresh", json={"refresh_token": second})
    assert again.status_code == 200


async def _age_rotation(db_session, token: str, seconds: float) -> None:
    db_session.expire_all()
    row = (
        await db_session.execute(
            select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(token))
        )
    ).scalar_one()
    row.rotated_at = datetime.now(UTC) - timedelta(seconds=seconds)
    await db_session.commit()


@pytest.mark.asyncio
async def test_reuse_after_grace_revokes_whole_family(client, db_session, test_user):
    first = await _issue(db_session, test_user)
    second = (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).json()["refresh_token"]
    other_family = await _issue(db_session, test_user)
    await _age_rotation(db_session, first, settings.REFRESH_REUSE_GRACE_SECONDS + 1)

    replay = await client.post(f"{BASE}/refresh", json={"refresh_token": first})
    assert replay.status_code == 401

    rows = {row.token_hash: row for row in await _rows(db_session)}
    assert rows[hash_refresh_token(second)].is_revoked
    assert not rows[hash_refresh_token(other_family)].is_revoked

    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": second})).status_code == 401
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": other_family})).status_code == 200


@pytest.mark.asyncio
async def test_reuse_within_grace_issues_a_pair_in_the_same_family(client, db_session, test_user):
    first = await _issue(db_session, test_user)
    second = (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).json()["refresh_token"]

    retry = await client.post(f"{BASE}/refresh", json={"refresh_token": first})
    assert retry.status_code == 200
    third = retry.json()["refresh_token"]
    assert third not in (first, second)

    rows = {row.token_hash: row for row in await _rows(db_session)}
    families = {rows[hash_refresh_token(t)].family_id for t in (first, second, third)}
    assert len(families) == 1
    assert not rows[hash_refresh_token(second)].is_revoked
    assert not rows[hash_refresh_token(third)].is_revoked
    # Both tabs stay signed in.
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": second})).status_code == 200
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": third})).status_code == 200


@pytest.mark.asyncio
async def test_token_revoked_by_logout_is_not_covered_by_grace(client, db_session, test_user):
    first = await _issue(db_session, test_user)
    second = (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).json()["refresh_token"]
    assert (await client.post(f"{BASE}/logout", json={"refresh_token": second})).status_code == 200

    # `first` was rotated seconds ago, but logout revoked its family.
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).status_code == 401
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": second})).status_code == 401


@pytest.mark.asyncio
async def test_family_revoked_after_grace_is_not_revived_by_a_later_reuse(client, db_session, test_user):
    first = await _issue(db_session, test_user)
    second = (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).json()["refresh_token"]
    await _age_rotation(db_session, first, settings.REFRESH_REUSE_GRACE_SECONDS + 1)
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).status_code == 401
    await _age_rotation(db_session, first, 1)
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).status_code == 401
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": second})).status_code == 401


@pytest.mark.asyncio
async def test_concurrent_refresh_both_succeed_in_one_family(client, db_session, test_user):
    token = await _issue(db_session, test_user)
    results = await asyncio.gather(
        *[client.post(f"{BASE}/refresh", json={"refresh_token": token}) for _ in range(2)]
    )
    assert [r.status_code for r in results] == [200, 200]
    issued = {r.json()["refresh_token"] for r in results}
    assert len(issued) == 2

    rows = await _rows(db_session)
    assert len(rows) == 3  # the original and one successor per request
    assert len({r.family_id for r in rows}) == 1
    assert sum(1 for r in rows if r.is_used) == 1 and not any(r.is_revoked for r in rows)


@pytest.mark.asyncio
async def test_legacy_raw_row_is_accepted_after_backfill_and_without_it(client, db_session, test_user):
    now = datetime.now(UTC)
    backfilled = create_refresh_token({"sub": str(test_user.id)})
    raw_only = create_refresh_token({"sub": str(test_user.id)})
    db_session.add_all(
        [
            RefreshToken(
                user_id=test_user.id, token=backfilled, token_hash=hash_refresh_token(backfilled),
                family_id=uuid.uuid4(), expires_at=now + timedelta(days=7),
            ),
            # Written by the previous release while the migration was running.
            RefreshToken(user_id=test_user.id, token=raw_only, expires_at=now + timedelta(days=7)),
        ]
    )
    await db_session.commit()

    for token in (backfilled, raw_only):
        r = await client.post(f"{BASE}/refresh", json={"refresh_token": token})
        assert r.status_code == 200, r.text

    rows = {row.token_hash: row for row in await _rows(db_session)}
    assert rows[hash_refresh_token(raw_only)].is_used
    assert all(row.token_hash and row.family_id for row in rows.values())


@pytest.mark.asyncio
async def test_expired_token_is_rejected_without_revoking_family(client, db_session, test_user):
    token = create_refresh_token({"sub": str(test_user.id)})
    family = uuid.uuid4()
    db_session.add(
        RefreshToken(
            user_id=test_user.id, token_hash=hash_refresh_token(token), family_id=family,
            expires_at=datetime.now(UTC) - timedelta(minutes=1),
        )
    )
    sibling = await _issue(db_session, test_user, family)
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": token})).status_code == 401
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": sibling})).status_code == 200


@pytest.mark.asyncio
async def test_logout_revokes_the_family(client, db_session, test_user):
    first = await _issue(db_session, test_user)
    second = (await client.post(f"{BASE}/refresh", json={"refresh_token": first})).json()["refresh_token"]
    other_device = await _issue(db_session, test_user)

    r = await client.post(f"{BASE}/logout", json={"refresh_token": second})
    assert r.status_code == 200

    rows = {row.token_hash: row for row in await _rows(db_session)}
    assert rows[hash_refresh_token(second)].is_revoked
    assert rows[hash_refresh_token(first)].is_revoked
    assert not rows[hash_refresh_token(other_device)].is_revoked
    assert (await client.post(f"{BASE}/refresh", json={"refresh_token": second})).status_code == 401
