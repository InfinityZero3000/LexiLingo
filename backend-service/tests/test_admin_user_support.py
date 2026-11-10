"""Support tools: wallet ledger, manual adjustments, admin-granted premium (real SQL, in-memory SQLite)."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import settings
from app.core.database import Base
from app.models.entitlement import UserEntitlement
from app.models.app_setting import AdminGemGrant, AppSetting
from app.models.gamification import ShopItem, UserInventory, UserWallet, WalletTransaction
from app.models.games import XPTransaction
from app.models.rbac import AuditLog
from app.models.user import User
from app.routes import admin_user_support as support
from app.services.entitlement_service import EntitlementService

TABLES = [
    User, UserWallet, WalletTransaction, XPTransaction, UserEntitlement, ShopItem, UserInventory, AuditLog,
    AppSetting, AdminGemGrant,
]


@pytest_asyncio.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(lambda c: Base.metadata.create_all(c, tables=[m.__table__ for m in TABLES]))
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        yield session
    await engine.dispose()


@pytest_asyncio.fixture
async def learner(db):
    user = User(id=uuid4(), email="l@x.io", username="learner", hashed_password="x", is_active=True)
    db.add(user)
    await db.commit()
    return user


ADMIN = SimpleNamespace(id=uuid4(), username="boss", role_level=2)


def _request():
    return SimpleNamespace(state=SimpleNamespace(), client=None, headers={})


async def _audits(db):
    return (await db.execute(select(AuditLog))).scalars().all()


@pytest.fixture(autouse=True)
def _no_cache():
    with patch.object(support, "delete_cached", new=AsyncMock()):
        yield


# ── wallet ────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_reading_a_wallet_never_creates_one(db, learner):
    resp = await support.get_user_wallet(learner.id, 20, 0, ADMIN, db)

    assert resp.data["balance"] == 0 and resp.data["transactions"] == []
    assert (await db.execute(select(UserWallet))).first() is None


@pytest.mark.asyncio
async def test_credit_adds_gems_writes_the_ledger_and_audits_the_reason(db, learner):
    await support.adjust_user_wallet(
        learner.id, support.WalletAdjustRequest(delta=50, reason="Lost reward"), _request(), ADMIN, db
    )

    wallet = (await db.execute(select(UserWallet))).scalar_one()
    tx = (await db.execute(select(WalletTransaction))).scalar_one()
    (audit,) = await _audits(db)
    assert wallet.gems == 50 and (tx.source, tx.amount) == ("admin_adjust", 50)
    assert (audit.action, audit.user_id) == ("wallet_adjust", ADMIN.id)
    assert "Lost reward" in audit.details

    listed = await support.get_user_wallet(learner.id, 20, 0, ADMIN, db)
    assert listed.data["balance"] == 50 and listed.data["total"] == 1


@pytest.mark.asyncio
async def test_debit_cannot_overdraw_and_changes_nothing(db, learner):
    await support.adjust_user_wallet(
        learner.id, support.WalletAdjustRequest(delta=10, reason="seed funds"), _request(), ADMIN, db
    )

    with pytest.raises(HTTPException) as err:
        await support.adjust_user_wallet(
            learner.id, support.WalletAdjustRequest(delta=-11, reason="refund too much"), _request(), ADMIN, db
        )
    await db.rollback()  # what get_db does on an HTTPException

    assert err.value.status_code == 400
    assert (await db.execute(select(UserWallet))).scalar_one().gems == 10
    assert len(await _audits(db)) == 1  # only the successful credit


@pytest.mark.asyncio
async def test_adjustment_is_capped_and_needs_a_real_reason(db, learner):
    with pytest.raises(HTTPException) as err:
        await support.adjust_user_wallet(
            learner.id,
            support.WalletAdjustRequest(delta=settings.SUPER_ADMIN_GIFT_MAX_GEMS + 1, reason="too many"),
            _request(), ADMIN, db,
        )
    assert err.value.status_code == 400

    for bad in ({"delta": 0, "reason": "valid reason"}, {"delta": 5, "reason": "no"}):
        with pytest.raises(ValidationError):
            support.WalletAdjustRequest(**bad)


# ── premium ───────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_grant_creates_an_active_admin_premium_and_revoke_ends_it(db, learner):
    granted = await support.grant_user_premium(
        learner.id, support.PremiumGrantRequest(days=30, reason="support goodwill"), _request(), ADMIN, db
    )
    assert granted.data["is_active"] is True and granted.data["source"] == "admin"
    assert await EntitlementService.is_active(db, learner.id) is True

    revoked = await support.revoke_user_premium(
        learner.id, support.PremiumRevokeRequest(reason="granted by mistake"), _request(), ADMIN, db
    )
    assert revoked.data["is_active"] is False
    assert await EntitlementService.is_active(db, learner.id) is False
    assert [a.action for a in await _audits(db)] == ["premium_grant", "premium_revoke"]


@pytest.mark.asyncio
async def test_a_paid_subscription_is_never_overwritten_or_revoked(db, learner):
    db.add(UserEntitlement(
        user_id=learner.id, entitlement_id="premium", status="active", source="revenuecat",
        expires_at=datetime.now(timezone.utc) + timedelta(days=90),
    ))
    await db.commit()

    with pytest.raises(HTTPException) as grant_err:
        await support.grant_user_premium(
            learner.id, support.PremiumGrantRequest(days=7, reason="extra goodwill"), _request(), ADMIN, db
        )
    with pytest.raises(HTTPException) as revoke_err:
        await support.revoke_user_premium(
            learner.id, support.PremiumRevokeRequest(reason="try to cancel"), _request(), ADMIN, db
        )

    assert grant_err.value.status_code == 409 and revoke_err.value.status_code == 409


class _Store:
    def __init__(self, entitlements):
        self._entitlements = entitlements

    async def get_subscriber_entitlements(self, _user_id):
        return self._entitlements


@pytest.mark.asyncio
async def test_sync_keeps_an_unexpired_admin_grant_when_the_store_has_nothing(db, learner):
    await support.grant_user_premium(
        learner.id, support.PremiumGrantRequest(days=10, reason="support goodwill"), _request(), ADMIN, db
    )

    row, degraded = await EntitlementService.sync(db, learner.id, client=_Store({}))

    assert (row.status, row.source, degraded) == ("active", "admin", False)


@pytest.mark.asyncio
async def test_sync_lets_a_real_subscription_replace_the_admin_grant(db, learner):
    await support.grant_user_premium(
        learner.id, support.PremiumGrantRequest(days=10, reason="support goodwill"), _request(), ADMIN, db
    )
    paid = {"premium": {"expires_date": (datetime.now(timezone.utc) + timedelta(days=365)).isoformat(),
                        "product_identifier": "yearly"}}

    row, _ = await EntitlementService.sync(db, learner.id, client=_Store(paid))

    assert (row.source, row.product_id) == ("revenuecat", "yearly")


@pytest.mark.asyncio
async def test_sync_still_expires_an_admin_grant_once_it_has_run_out(db, learner):
    db.add(UserEntitlement(
        user_id=learner.id, entitlement_id="premium", status="active", source="admin",
        expires_at=datetime.now(timezone.utc) - timedelta(days=1),
    ))
    await db.commit()

    row, _ = await EntitlementService.sync(db, learner.id, client=_Store({}))

    assert (row.status, row.source) == ("none", "revenuecat")


# ── inventory ─────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_inventory_lists_owned_items_with_names(db, learner):
    item = ShopItem(id=uuid4(), name="Streak Freeze", description="d", item_type="streak_freeze", price_gems=10)
    db.add_all([item, UserInventory(user_id=learner.id, shop_item_id=item.id, quantity=2)])
    await db.commit()

    resp = await support.get_user_inventory(learner.id, ADMIN, db)

    assert [(i["name"], i["quantity"]) for i in resp.data["items"]] == [("Streak Freeze", 2)]


@pytest.mark.asyncio
async def test_unknown_user_is_a_404(db):
    with pytest.raises(HTTPException) as err:
        await support.get_user_wallet(uuid4(), 20, 0, ADMIN, db)
    assert err.value.status_code == 404


@pytest.mark.asyncio
async def test_xp_history_is_newest_first_and_paged(db, learner):
    now = datetime.now(timezone.utc)
    for i in range(3):
        db.add(XPTransaction(
            user_id=learner.id, amount=10 * (i + 1), base_amount=10 * (i + 1), source="lesson",
            created_at=now - timedelta(minutes=10 - i),
        ))
    await db.commit()

    page = await support.get_user_xp_transactions(learner.id, 2, 0, ADMIN, db)

    assert page.data["total"] == 3
    assert [t["amount"] for t in page.data["transactions"]] == [30, 20]
