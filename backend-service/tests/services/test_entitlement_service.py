from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings
from app.core.database import Base
from app.models.entitlement import UserEntitlement
from app.models.user import User
from app.services.entitlement_service import EntitlementService
from app.services.revenuecat_client import RevenueCatClient, RevenueCatUnavailableError


@pytest.fixture
async def db_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [User.__table__, UserEntitlement.__table__]
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=tables,
            )
        )

    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


@pytest.fixture
async def test_user(db_session):
    user = User(
        email="entitlement@example.com",
        username="entitlement_user",
        hashed_password="not-used",
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


class _FakeRevenueCatClient:
    def __init__(self, entitlements: dict[str, dict] | None = None, *, raises: bool = False):
        self._entitlements = entitlements or {}
        self._raises = raises

    async def get_subscriber_entitlements(self, app_user_id: str) -> dict[str, dict]:
        if self._raises:
            raise RevenueCatUnavailableError("simulated outage")
        return self._entitlements


async def test_sync_creates_active_row_for_lifetime_grant(db_session, test_user):
    client = _FakeRevenueCatClient(
        {"premium": {"product_identifier": "lifetime_premium", "expires_date": None}}
    )

    row, degraded = await EntitlementService.sync(db_session, test_user.id, client=client)

    assert degraded is False
    assert row.status == "active"
    assert row.expires_at is None
    assert await EntitlementService.is_active(db_session, test_user.id) is True


async def test_sync_marks_expired_grant_as_inactive(db_session, test_user):
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat().replace("+00:00", "Z")
    client = _FakeRevenueCatClient(
        {"premium": {"product_identifier": "monthly_premium", "expires_date": past}}
    )

    row, degraded = await EntitlementService.sync(db_session, test_user.id, client=client)

    assert degraded is False
    assert row.status == "expired"
    assert await EntitlementService.is_active(db_session, test_user.id) is False


async def test_sync_with_no_grant_records_none_status(db_session, test_user):
    client = _FakeRevenueCatClient({})

    row, degraded = await EntitlementService.sync(db_session, test_user.id, client=client)

    assert degraded is False
    assert row.status == "none"
    assert await EntitlementService.is_active(db_session, test_user.id) is False


async def test_sync_outage_preserves_prior_active_state(db_session, test_user):
    good_client = _FakeRevenueCatClient(
        {"premium": {"product_identifier": "lifetime_premium", "expires_date": None}}
    )
    await EntitlementService.sync(db_session, test_user.id, client=good_client)

    failing_client = _FakeRevenueCatClient(raises=True)
    row, degraded = await EntitlementService.sync(db_session, test_user.id, client=failing_client)

    assert degraded is True
    assert row is not None
    assert row.status == "active"
    # A degraded sync does not touch the stored row.
    assert await EntitlementService.is_active(db_session, test_user.id) is True


async def test_sync_outage_with_no_prior_row_stays_unentitled(db_session, test_user):
    failing_client = _FakeRevenueCatClient(raises=True)

    row, degraded = await EntitlementService.sync(db_session, test_user.id, client=failing_client)

    assert degraded is True
    assert row is None
    assert await EntitlementService.is_active(db_session, test_user.id) is False


async def test_sync_upserts_single_row_per_user_entitlement(db_session, test_user):
    client_a = _FakeRevenueCatClient(
        {"premium": {"product_identifier": "monthly_premium", "expires_date": None}}
    )
    await EntitlementService.sync(db_session, test_user.id, client=client_a)

    client_b = _FakeRevenueCatClient(
        {"premium": {"product_identifier": "yearly_premium", "expires_date": None}}
    )
    await EntitlementService.sync(db_session, test_user.id, client=client_b)

    result = await db_session.execute(
        select(UserEntitlement).where(UserEntitlement.user_id == test_user.id)
    )
    rows = result.scalars().all()
    assert len(rows) == 1
    assert rows[0].product_id == "yearly_premium"


async def test_missing_secret_key_is_degraded_not_a_500(db_session, test_user, monkeypatch):
    """REVENUECAT_SECRET_API_KEY is unset in every environment today — this
    must degrade gracefully, not raise an unhandled exception through the
    /entitlements/sync route on every login."""
    monkeypatch.setattr(settings, "REVENUECAT_SECRET_API_KEY", None)

    row, degraded = await EntitlementService.sync(db_session, test_user.id, client=RevenueCatClient())

    assert degraded is True
    assert row is None
