"""Concurrency regression test for BACKEND_AUDIT_REPORT.md #1
(reward/XP atomicity): two simultaneous requests awarding XP for the same
(user_id, source, source_id) must produce exactly one XPTransaction.

Requires a real Postgres connection (TEST_DATABASE_URL) — row locking and
unique-constraint races aren't meaningfully testable against SQLite. Run
this against the dev stack: `docker compose -f docker-compose.dev.yml up`.
"""

import asyncio

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.models.games import XPTransaction
from app.models.user import User
from app.services.xp_service import award_xp_transaction


async def test_concurrent_same_source_id_awards_xp_exactly_once(db_engine, test_user):
    """Two requests racing to award XP for the identical (source, source_id)
    — e.g. a double-tapped "complete lesson" button — must not double-award."""
    factory = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)

    async def award(session: AsyncSession) -> None:
        result = await session.execute(select(User).where(User.id == test_user.id))
        user = result.scalar_one()
        try:
            await award_xp_transaction(
                db=session,
                user=user,
                source="game",
                base_xp=20,
                source_id="race-test-session-1",
            )
        except Exception:
            # A losing request is expected to fail closed (409/rollback),
            # not silently succeed with a duplicate award.
            await session.rollback()

    async with factory() as session_a, factory() as session_b:
        await asyncio.gather(award(session_a), award(session_b))

    async with factory() as verify_session:
        result = await verify_session.execute(
            select(XPTransaction).where(
                XPTransaction.user_id == test_user.id,
                XPTransaction.source == "game",
                XPTransaction.source_id == "race-test-session-1",
            )
        )
        transactions = result.scalars().all()

    assert len(transactions) == 1
