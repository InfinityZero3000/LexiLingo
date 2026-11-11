"""Social follow race, run against a real Postgres.

`SocialCRUD.follow_user` checked "already following" then inserted, with no
IntegrityError handling — a double-tap on the Follow button (or any two
concurrent requests) could both pass the check and the second insert hit
`uq_user_following` as an unhandled exception, surfacing to the client as a
500 instead of the same "Already following this user" the first request's
check would have returned on its own.
"""

import asyncio

import pytest
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import async_sessionmaker, AsyncSession

from app.core.database import get_db
from app.core.security import create_access_token
from app.main import app
from app.models.gamification import UserFollowing
from app.models.user import User


def _auth(user_id):
    return {"Authorization": f"Bearer {create_access_token(data={'sub': str(user_id)})}"}


@pytest.mark.asyncio
async def test_concurrent_follow_requests_never_500_and_create_one_row(
    db_engine, test_user
):
    maker = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with maker() as s:
        target = User(
            email="target@example.com",
            username="targetuser",
            hashed_password="x",
            display_name="Target User",
            is_active=True,
            is_verified=True,
            native_language="vi",
            target_language="en",
            level="beginner",
        )
        s.add(target)
        await s.commit()
        target_id = target.id

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
                        f"/api/v1/gamification/users/{target_id}/follow",
                        headers=_auth(test_user.id),
                    )
                    for _ in range(2)
                ]
            )
    finally:
        app.dependency_overrides.clear()

    # Neither response may be a 500 — one succeeds, the other reports the
    # already-following state cleanly, in either order.
    assert all(r.status_code in (200, 400) for r in results), [
        (r.status_code, r.text) for r in results
    ]

    async with maker() as s:
        count = (
            await s.execute(
                select(func.count()).select_from(UserFollowing).where(
                    UserFollowing.follower_id == test_user.id,
                    UserFollowing.following_id == target_id,
                )
            )
        ).scalar()
    assert count == 1
