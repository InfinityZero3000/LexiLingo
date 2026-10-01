"""Gem-economy exploits, run against a real Postgres.

The shop computed cost as price × quantity with no lower bound on quantity, and
spend_gems' balance check (`gems < amount`) is never true for a negative
amount — so `quantity=-1000` *credited* the wallet. Mocked sessions cannot show
this; the arithmetic only goes wrong on real rows.
"""

import asyncio
from datetime import date

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, AsyncSession

from app.core.database import get_db
from app.core.security import create_access_token
from app.crud.gamification import WalletCRUD
from app.main import app
from app.models.gamification import ShopItem, UserInventory, UserWallet
from app.models.progress import Streak


def _auth(user_id):
    return {"Authorization": f"Bearer {create_access_token(data={'sub': str(user_id)})}"}


async def _seed(db, user_id, gems=100):
    item = ShopItem(
        name="Streak Freeze",
        description="x",
        item_type="streak_freeze",
        price_gems=25,
        is_available=True,
    )
    db.add_all([item, UserWallet(user_id=user_id, gems=gems)])
    await db.commit()
    return item.id


async def _gems(db, user_id):
    db.expire_all()
    return (
        await db.execute(select(UserWallet.gems).where(UserWallet.user_id == user_id))
    ).scalar()


@pytest.mark.asyncio
@pytest.mark.parametrize("quantity", [-1000, -1, 0, 100])
async def test_out_of_range_quantity_is_rejected(async_client, db_session, test_user, quantity):
    uid = test_user.id
    item_id = await _seed(db_session, uid)

    resp = await async_client.post(
        "/api/v1/gamification/shop/purchase",
        json={"item_id": str(item_id), "quantity": quantity},
        headers=_auth(uid),
    )

    assert resp.status_code == 422
    assert await _gems(db_session, uid) == 100
    inv = (
        await db_session.execute(select(UserInventory).where(UserInventory.user_id == uid))
    ).scalar_one_or_none()
    assert inv is None


@pytest.mark.asyncio
async def test_valid_purchase_still_spends(async_client, db_session, test_user):
    uid = test_user.id
    item_id = await _seed(db_session, uid)

    resp = await async_client.post(
        "/api/v1/gamification/shop/purchase",
        json={"item_id": str(item_id), "quantity": 2},
        headers=_auth(uid),
    )

    assert resp.status_code == 200, resp.text
    assert await _gems(db_session, uid) == 50


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", [0, -50])
async def test_shared_gem_functions_reject_non_positive_amounts(db_session, test_user, amount):
    """The guard lives in the shared functions, so no future caller reopens it."""
    with pytest.raises(ValueError):
        await WalletCRUD.spend_gems(db_session, test_user.id, amount, source="t")
    with pytest.raises(ValueError):
        await WalletCRUD.add_gems(db_session, test_user.id, amount, source="t")


@pytest.mark.asyncio
async def test_daily_streak_reward_pays_once_under_concurrency(db_engine, test_user):
    """Two claims in flight together used to both pass the once-a-day check."""
    uid = test_user.id
    maker = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with maker() as s:
        s.add_all([
            Streak(user_id=uid, current_streak=3, last_activity_date=date.today()),
            UserWallet(user_id=uid, gems=0),
        ])
        await s.commit()

    # One session per request, as in production — a shared session would
    # serialise them and hide the race.
    async def _db():
        async with maker() as s:
            yield s

    app.dependency_overrides[get_db] = _db
    try:
        from httpx import ASGITransport, AsyncClient

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
            results = await asyncio.gather(*[
                c.post("/api/v1/progress/streak/claim-daily-reward", headers=_auth(uid))
                for _ in range(2)
            ])
    finally:
        app.dependency_overrides.clear()

    assert sorted(r.status_code for r in results) == [200, 400]
    async with maker() as s:
        gems = (await s.execute(select(UserWallet.gems).where(UserWallet.user_id == uid))).scalar()
    assert gems == 15  # day 3 of the cycle, paid exactly once


@pytest.mark.asyncio
async def test_one_streak_freeze_cannot_be_used_twice_concurrently(
    db_engine, test_user, monkeypatch
):
    """Two uses in flight on quantity=1 both passed the check before the lock."""
    from app.services.item_effects_service import ItemEffectsService

    # Widen the gap between the quantity check and the decrement so the race
    # is certain rather than timing-dependent; without it both requests can
    # happen to finish one after the other and the test passes on broken code.
    original = ItemEffectsService._handle_streak_freeze

    async def slow_handler(self, **kw):
        await asyncio.sleep(0.2)
        return await original(self, **kw)

    monkeypatch.setattr(ItemEffectsService, "_handle_streak_freeze", slow_handler)
    uid = test_user.id
    maker = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with maker() as s:
        item = ShopItem(
            name="Streak Freeze", description="x", item_type="streak_freeze",
            price_gems=25, is_available=True,
        )
        s.add(item)
        await s.flush()
        inv = UserInventory(user_id=uid, shop_item_id=item.id, quantity=1)
        s.add_all([inv, Streak(user_id=uid, freeze_count=0)])
        await s.commit()
        inv_id = inv.id

    async def _db():
        async with maker() as s:
            yield s

    app.dependency_overrides[get_db] = _db
    try:
        from httpx import ASGITransport, AsyncClient

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
            results = await asyncio.gather(*[
                c.post(
                    "/api/v1/gamification/inventory/use",
                    json={"inventory_id": str(inv_id)},
                    headers=_auth(uid),
                )
                for _ in range(2)
            ])
    finally:
        app.dependency_overrides.clear()

    async with maker() as s:
        freezes = (await s.execute(select(Streak.freeze_count).where(Streak.user_id == uid))).scalar()
        qty = (await s.execute(select(UserInventory.quantity).where(UserInventory.id == inv_id))).scalar()
    # Without the lock both requests answered 200. For a streak freeze the
    # second write then lost-updates the first, so the final row looks right —
    # the status codes are what show one item being spent twice.
    assert sorted(r.status_code for r in results) == [200, 400]
    assert (freezes, qty) == (1, 0)
