"""Gem gifts and adjustments obey editable caps, a daily budget, and leave a ledger row (real SQL, SQLite)."""
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import settings
from app.core.database import Base
from app.models.app_setting import AdminGemGrant, AppSetting
from app.models.gamification import ShopItem, UserInventory, UserWallet, WalletTransaction
from app.models.notification import Notification
from app.models.rbac import AuditLog
from app.models.user import User
from app.routes import admin_gem_ledger as ledger
from app.routes import user_management as um
from app.services import gem_limits

TABLES = [User, UserWallet, WalletTransaction, ShopItem, UserInventory, Notification, AuditLog, AppSetting, AdminGemGrant]


@pytest_asyncio.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(lambda c: Base.metadata.create_all(c, tables=[m.__table__ for m in TABLES]))
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        yield session
    await engine.dispose()


async def _user(db, name):
    user = User(id=uuid4(), email=f"{name}@x.io", username=name, hashed_password="x", is_active=True)
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def learner(db):
    return await _user(db, "learner")


@pytest_asyncio.fixture
async def admin(db):
    user = await _user(db, "boss")
    return SimpleNamespace(id=user.id, username="boss", role_level=1)


def _request():
    return SimpleNamespace(state=SimpleNamespace(), client=None, headers={})


def _gems(amount, reason="support goodwill"):
    return um.GiftRequest(gift_type="gems", amount=amount, reason=reason)


async def _gift(db, admin, learner, amount):
    with patch("app.core.cache.delete_cached", new=AsyncMock()):
        return await um.send_gift_to_user(learner.id, _gems(amount), _request(), admin, db)


@pytest.mark.asyncio
async def test_gift_needs_a_reason_and_cannot_target_yourself(db, admin, learner):
    with pytest.raises(Exception):
        um.GiftRequest(gift_type="gems", amount=5, reason="no")
    with pytest.raises(HTTPException) as err:
        await um.send_gift_to_user(admin.id, _gems(5), _request(), admin, db)
    assert err.value.status_code == 400


@pytest.mark.asyncio
async def test_gift_over_the_per_action_cap_is_refused_and_leaves_no_ledger_row(db, admin, learner):
    with pytest.raises(HTTPException) as err:
        await _gift(db, admin, learner, settings.ADMIN_GIFT_MAX_GEMS + 1)
    await db.rollback()
    assert err.value.status_code == 400
    assert (await db.execute(select(AdminGemGrant))).scalars().all() == []


@pytest.mark.asyncio
async def test_successful_gift_is_recorded_in_the_ledger_with_actor_and_reason(db, admin, learner):
    await _gift(db, admin, learner, 50)

    (grant,) = (await db.execute(select(AdminGemGrant))).scalars().all()
    assert (grant.actor_id, grant.user_id, grant.kind, grant.amount) == (admin.id, learner.id, "gift", 50)
    assert grant.reason == "support goodwill"
    assert (await db.execute(select(UserWallet))).scalar_one().gems == 50


@pytest.mark.asyncio
async def test_daily_budget_stops_the_gift_that_would_exceed_it(db, admin, learner):
    await ledger.update_gem_limits(
        ledger.GemLimitsUpdate(budget_admin=120, gift_max_admin=100),
        _request(), SimpleNamespace(id=admin.id, username="root", role_level=2), db,
    )
    await _gift(db, admin, learner, 100)

    with pytest.raises(HTTPException) as err:
        await _gift(db, admin, learner, 30)
    await db.rollback()

    assert err.value.status_code == 400 and "budget" in err.value.detail
    usage = await gem_limits.usage_for(db, admin)
    assert (usage["spent_today"], usage["remaining_today"]) == (100, 20)


@pytest.mark.asyncio
async def test_super_admin_edits_are_stored_audited_and_override_the_env_default(db, admin):
    root = SimpleNamespace(id=admin.id, username="root", role_level=2)
    result = await ledger.update_gem_limits(ledger.GemLimitsUpdate(gift_max_admin=7), _request(), root, db)

    assert result.data["config"]["gift_max_admin"] == 7
    assert result.data["config"]["gift_max_super_admin"] == settings.SUPER_ADMIN_GIFT_MAX_GEMS
    (audit,) = (await db.execute(select(AuditLog))).scalars().all()
    assert audit.action == "gem_limits_update"


@pytest.mark.asyncio
async def test_item_gift_quantity_is_capped(db, admin, learner):
    item = ShopItem(id=uuid4(), name="Boost", description="x", item_type="boost", price_gems=1)
    db.add(item)
    await db.commit()
    body = um.GiftRequest(
        gift_type="shop_item", shop_item_id=item.id, amount=settings.ADMIN_GIFT_MAX_ITEM_QTY + 1, reason="compensation"
    )
    with pytest.raises(HTTPException) as err:
        await um.send_gift_to_user(learner.id, body, _request(), admin, db)
    assert err.value.status_code == 400


@pytest.mark.asyncio
async def test_plain_admin_sees_only_their_own_grants(db, admin, learner):
    await _gift(db, admin, learner, 10)
    other = SimpleNamespace(id=uuid4(), username="other", role_level=1)
    db.add(AdminGemGrant(actor_id=other.id, user_id=learner.id, kind="gift", amount=5, reason="other admin"))
    await db.commit()

    mine = await ledger.list_gem_grants(None, None, None, None, None, 20, 0, admin, db)
    root = SimpleNamespace(id=uuid4(), username="root", role_level=2)
    everyone = await ledger.list_gem_grants(None, None, None, None, None, 20, 0, root, db)

    assert mine.data["total"] == 1 and mine.data["items"][0]["actor"]["username"] == "boss"
    assert everyone.data["total"] == 2
