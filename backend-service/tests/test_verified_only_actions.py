"""Unverified accounts sign in, but cannot farm referral pay-outs or spend gems."""
import uuid

import pytest

from app.core.security import create_access_token
from app.models.user import User


async def _user(db_session, *, verified: bool) -> User:
    user = User(
        email=f"{uuid.uuid4().hex[:8]}@example.com",
        username=uuid.uuid4().hex[:10],
        hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
        is_active=True,
        is_verified=verified,
    )
    db_session.add(user)
    await db_session.commit()
    return user


def _auth(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token({'sub': str(user.id)})}"}


@pytest.mark.asyncio
async def test_unverified_cannot_claim_a_referral(async_client, db_session):
    user = await _user(db_session, verified=False)
    response = await async_client.post("/api/v1/referral/claim/ABCDEF", headers=_auth(user))
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_unverified_cannot_buy_in_the_shop(async_client, db_session):
    user = await _user(db_session, verified=False)
    response = await async_client.post(
        "/api/v1/gamification/shop/purchase",
        json={"item_id": str(uuid.uuid4()), "quantity": 1},
        headers=_auth(user),
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_verified_reaches_the_referral_handler(async_client, db_session):
    user = await _user(db_session, verified=True)
    response = await async_client.post("/api/v1/referral/claim/ABCDEF", headers=_auth(user))
    # The code does not exist, so the handler answers; the point is it was not a 403.
    assert response.status_code != 403
