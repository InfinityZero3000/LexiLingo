"""A key the admin creates really authenticates once, and stops working when revoked or expired."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
import pytest_asyncio
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.database import Base
from app.core.partner_auth import require_partner_api_key
from app.models.partner import PartnerApiKey
from app.models.rbac import AuditLog
from app.routes import admin_partner_keys as keys

ADMIN = SimpleNamespace(id=uuid4(), username="boss", role_level=2)


@pytest_asyncio.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(lambda c: Base.metadata.create_all(c, tables=[PartnerApiKey.__table__, AuditLog.__table__]))
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        yield session
    await engine.dispose()


def _request():
    return SimpleNamespace(state=SimpleNamespace(), client=None, headers={})


async def _create(db, **over):
    body = keys.PartnerKeyCreate(owner="Acme Partners", **over)
    return (await keys.create_partner_key(body, _request(), ADMIN, db)).data


@pytest.mark.asyncio
async def test_created_key_authenticates_and_only_its_hash_is_stored(db):
    created = await _create(db)

    assert await require_partner_api_key(api_key=created["key"], db=db) == created["key_id"]
    stored = (await db.execute(select(PartnerApiKey))).scalar_one()
    assert created["key"] not in (stored.key_hash, stored.key_id)
    assert len(stored.key_hash) == 64


@pytest.mark.asyncio
async def test_the_raw_key_is_never_listed_again(db):
    await _create(db)

    listed = (await keys.list_partner_keys(ADMIN, db)).data

    assert len(listed) == 1
    assert "key" not in listed[0] and "key_hash" not in listed[0]
    assert listed[0]["status"] == "active"


@pytest.mark.asyncio
async def test_a_revoked_key_stops_working_and_cannot_be_revoked_twice(db):
    created = await _create(db)

    await keys.revoke_partner_key(UUID(created["id"]), _request(), ADMIN, db)

    with pytest.raises(HTTPException) as rejected:
        await require_partner_api_key(api_key=created["key"], db=db)
    assert rejected.value.status_code == 401
    with pytest.raises(HTTPException) as again:
        await keys.revoke_partner_key(UUID(created["id"]), _request(), ADMIN, db)
    assert again.value.status_code == 409
    assert (await keys.list_partner_keys(ADMIN, db)).data[0]["status"] == "revoked"


@pytest.mark.asyncio
async def test_an_expired_key_is_reported_and_rejected(db):
    created = await _create(db, expires_in_days=1)
    stored = (await db.execute(select(PartnerApiKey))).scalar_one()
    stored.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    await db.commit()

    assert (await keys.list_partner_keys(ADMIN, db)).data[0]["status"] == "expired"
    with pytest.raises(HTTPException):
        await require_partner_api_key(api_key=created["key"], db=db)


@pytest.mark.asyncio
async def test_create_and_revoke_are_audited_without_the_secret(db):
    created = await _create(db)
    await keys.revoke_partner_key(UUID(created["id"]), _request(), ADMIN, db)

    audits = (await db.execute(select(AuditLog).order_by(AuditLog.created_at))).scalars().all()

    assert [a.action for a in audits] == ["partner_key_create", "partner_key_revoke"]
    assert all(created["key"] not in (a.details or "") for a in audits)
    assert audits[0].resource_id == created["key_id"]


def test_owner_and_lifetime_are_validated():
    for bad in ({"owner": "x"}, {"owner": "Acme", "expires_in_days": 0}, {"owner": "Acme", "expires_in_days": 1000}):
        with pytest.raises(ValidationError):
            keys.PartnerKeyCreate(**bad)


def test_partner_key_management_is_super_admin_only():
    from app.core.dependencies import get_current_super_admin

    for route in keys.router.routes:
        assert get_current_super_admin in [d.call for d in route.dependant.dependencies], route.path
