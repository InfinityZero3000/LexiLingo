"""Shop purchase race conditions, run against a real Postgres.

`ShopCRUD.purchase_item` reads `ShopItem.stock_quantity` and, for avatars,
"do I already own this" with no row lock, then decrements stock / inserts
the inventory row later in the same call. Two concurrent purchases can both
pass the check before either writes — the same read-check-write shape the
2026-09-30 audit already found and fixed for the daily streak reward and
`/inventory/use` (see test_gem_economy_db.py), but `purchase_item` itself was
not covered by that pass. `spend_gems` already locks the wallet row
(`with_for_update`), so gems cannot be double-spent in isolation — what races
here is the shop's own state: stock and "owned once" avatars.
"""

import asyncio

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, AsyncSession

from app.core.database import get_db
from app.core.security import create_access_token
from app.main import app
from app.models.gamification import ShopItem, UserInventory, UserWallet


def _auth(user_id):
    return {"Authorization": f"Bearer {create_access_token(data={'sub': str(user_id)})}"}


@pytest.mark.asyncio
async def test_concurrent_purchases_cannot_oversell_limited_stock(db_engine, test_user):
    # No artificial delay needed: purchase_item locks the ShopItem row with
    # with_for_update(), so the second request blocks at that SELECT — on
    # Postgres itself, not on timing luck — until the first transaction
    # commits or rolls back.
    uid = test_user.id
    maker = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with maker() as s:
        item = ShopItem(
            name="Limited Hoodie",
            description="x",
            item_type="cosmetic",
            price_gems=10,
            is_available=True,
            stock_quantity=1,
        )
        s.add_all([item, UserWallet(user_id=uid, gems=100)])
        await s.commit()
        item_id = item.id

    async def _db():
        async with maker() as s:
            yield s

    app.dependency_overrides[get_db] = _db
    try:
        from httpx import ASGITransport, AsyncClient

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
            results = await asyncio.gather(
                *[
                    c.post(
                        "/api/v1/gamification/shop/purchase",
                        json={"item_id": str(item_id), "quantity": 1},
                        headers=_auth(uid),
                    )
                    for _ in range(2)
                ]
            )
    finally:
        app.dependency_overrides.clear()

    assert sorted(r.status_code for r in results) == [200, 400], [
        r.text for r in results
    ]

    async with maker() as s:
        s.expire_all()
        remaining = (
            await s.execute(
                select(ShopItem.stock_quantity).where(ShopItem.id == item_id)
            )
        ).scalar()
        total_granted = (
            await s.execute(
                select(UserInventory.quantity).where(
                    UserInventory.user_id == uid, UserInventory.shop_item_id == item_id
                )
            )
        ).scalar()
    assert remaining == 0, f"stock should be exactly sold out, got {remaining}"
    assert total_granted == 1, f"exactly one unit should have been granted, got {total_granted}"


@pytest.mark.asyncio
async def test_concurrent_purchases_cannot_double_own_a_one_time_avatar(
    db_engine, test_user
):
    uid = test_user.id
    maker = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with maker() as s:
        item = ShopItem(
            name="Golden Avatar",
            description="x",
            item_type="avatar",
            price_gems=30,
            is_available=True,
        )
        s.add_all([item, UserWallet(user_id=uid, gems=100)])
        await s.commit()
        item_id = item.id

    async def _db():
        async with maker() as s:
            yield s

    app.dependency_overrides[get_db] = _db
    try:
        from httpx import ASGITransport, AsyncClient

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
            results = await asyncio.gather(
                *[
                    c.post(
                        "/api/v1/gamification/shop/purchase",
                        json={"item_id": str(item_id), "quantity": 1},
                        headers=_auth(uid),
                    )
                    for _ in range(2)
                ]
            )
    finally:
        app.dependency_overrides.clear()

    assert sorted(r.status_code for r in results) == [200, 400], [
        r.text for r in results
    ]

    async with maker() as s:
        s.expire_all()
        rows = (
            (
                await s.execute(
                    select(UserInventory).where(
                        UserInventory.user_id == uid,
                        UserInventory.shop_item_id == item_id,
                    )
                )
            )
            .scalars()
            .all()
        )
        gems = (
            await s.execute(select(UserWallet.gems).where(UserWallet.user_id == uid))
        ).scalar()
    assert len(rows) == 1, f"avatar must be owned exactly once, got {len(rows)} rows"
    assert gems == 70, f"must be charged exactly once (100 - 30), got {gems}"
