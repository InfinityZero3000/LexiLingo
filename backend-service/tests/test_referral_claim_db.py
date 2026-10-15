"""Referral claims against a real Postgres, not a MagicMock session.

The old claim built WalletTransaction rows without wallet_id or balance_after —
both NOT NULL — so every real claim died with an IntegrityError on commit while
the mocked suite stayed green. These run the whole route on the test database.
"""

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

from app.core.security import create_access_token
from app.models.gamification import UserWallet, WalletTransaction
from app.models.user import User

BASE = "/api/v1/referral"
_HASH = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu"


async def _user(db, name, *, code=None, created_at=None, referred_by=None):
    user = User(
        email=f"{name}@example.com",
        username=name,
        hashed_password=_HASH,
        display_name=name,
        is_active=True,
        is_verified=True,
        referral_code=code,
        referred_by=referred_by,
    )
    if created_at is not None:
        user.created_at = created_at
    db.add(user)
    await db.commit()
    await db.refresh(user)
    # Plain values, not the ORM row: _gems() expires the session, and touching
    # an expired attribute afterwards triggers a sync lazy-load.
    return _U(user.id, user.referral_code)


class _U:
    def __init__(self, id, code):
        self.id = id
        self.code = code


def _auth(user):
    return {"Authorization": f"Bearer {create_access_token(data={'sub': str(user.id)})}"}


async def _gems(db, user_id):
    db.expire_all()
    return (
        await db.execute(select(UserWallet.gems).where(UserWallet.user_id == user_id))
    ).scalar()


@pytest.mark.asyncio
async def test_claim_pays_both_and_creates_missing_wallets(async_client, db_session):
    referrer = await _user(db_session, "referrer", code="REFER123")
    newbie = await _user(db_session, "newbie")

    resp = await async_client.post(f"{BASE}/claim/REFER123", headers=_auth(newbie))

    assert resp.status_code == 200, resp.text
    assert resp.json()["gems_awarded"] == 50
    # Neither user had a wallet row; the old code skipped the gems and still
    # announced "you both received 50 gems".
    assert await _gems(db_session, referrer.id) == 50
    assert await _gems(db_session, newbie.id) == 50


@pytest.mark.asyncio
async def test_old_account_cannot_claim(async_client, db_session):
    await _user(db_session, "referrer2", code="REFER234")
    veteran = await _user(
        db_session,
        "veteran",
        created_at=datetime.now(timezone.utc) - timedelta(days=30),
    )

    resp = await async_client.post(f"{BASE}/claim/REFER234", headers=_auth(veteran))

    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_cannot_claim_the_code_of_someone_you_referred(async_client, db_session):
    a = await _user(db_session, "alice", code="ALICE123")
    await _user(db_session, "bob", code="BOBBY123", referred_by=a.id)

    resp = await async_client.post(f"{BASE}/claim/BOBBY123", headers=_auth(a))

    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_referrer_stops_being_paid_past_the_daily_cap(
    async_client, db_session, monkeypatch
):
    monkeypatch.setattr("app.routes.referral._MAX_REWARDED_REFERRALS_PER_DAY", 2)
    referrer = await _user(db_session, "farmer", code="FARM1234")

    for i in range(3):
        alt = await _user(db_session, f"alt{i}")
        resp = await async_client.post(f"{BASE}/claim/FARM1234", headers=_auth(alt))
        assert resp.status_code == 200, resp.text
        # The new account is always welcomed, cap or not.
        assert await _gems(db_session, alt.id) == 50

    assert await _gems(db_session, referrer.id) == 100  # 2 paid, third capped
    referred = (
        await db_session.execute(
            select(func.count(User.id)).where(User.referred_by == referrer.id)
        )
    ).scalar()
    assert referred == 3  # the link is still recorded


@pytest.mark.asyncio
async def test_every_transaction_row_is_complete(async_client, db_session):
    await _user(db_session, "ref5", code="REFER555")
    newbie = await _user(db_session, "newbie5")

    await async_client.post(f"{BASE}/claim/REFER555", headers=_auth(newbie))

    rows = (await db_session.execute(select(WalletTransaction))).scalars().all()
    assert len(rows) == 2
    assert all(r.wallet_id and r.balance_after == 50 for r in rows)
