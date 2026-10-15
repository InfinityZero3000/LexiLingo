"""Real concurrent-request race tests — audit items #1/#2.

Each test drives two independent AsyncSessions (separate DB connections,
NullPool) against the same row with asyncio.gather, so Postgres — not
Python — decides the interleaving. This is what the audit's "Gap" list
called for: a genuine two-requests-at-once test, not a sequential one.
"""

import asyncio
from datetime import date, datetime, timezone

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.crud.gamification import LeaderboardCRUD, WalletCRUD
from app.models.gamification import ChallengeRewardClaim, LeaderboardEntry, WalletTransaction
from app.models.user import User


def _sessionmaker(db_engine):
    return async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)


@pytest.mark.asyncio
async def test_concurrent_add_gems_has_no_lost_update(db_engine, test_user: User):
    """Two simultaneous gem grants for the same user must both land —
    the with_for_update() row lock is what audit item #1 asked for."""
    make_session = _sessionmaker(db_engine)

    # Pre-create the wallet so both branches race on add_gems' lock, not on
    # get_or_create_wallet's own race handling (that's a separate concern).
    async with make_session() as setup_session:
        await WalletCRUD.get_or_create_wallet(setup_session, test_user.id)

    async def grant(amount: int, source: str):
        async with make_session() as session:
            await WalletCRUD.add_gems(session, test_user.id, amount, source=source)

    await asyncio.gather(grant(30, "race_a"), grant(70, "race_b"))

    async with make_session() as verify_session:
        wallet = await WalletCRUD.get_or_create_wallet(verify_session, test_user.id)
        assert wallet.gems == 100
        assert wallet.total_gems_earned == 100

        tx_count = await verify_session.execute(
            select(func.count()).select_from(WalletTransaction).where(
                WalletTransaction.user_id == test_user.id
            )
        )
        assert tx_count.scalar() == 2


@pytest.mark.asyncio
async def test_concurrent_challenge_claim_only_one_wins(db_engine, test_user: User):
    """Two simultaneous claims of the same daily challenge must not both
    pay out — the unique index on (user_id, challenge_id, claim_date) is
    the real guard behind the route's pre-check (audit item #2)."""
    make_session = _sessionmaker(db_engine)
    claim_date = datetime.combine(date.today(), datetime.min.time()).replace(tzinfo=timezone.utc)

    async def try_claim() -> bool:
        async with make_session() as session:
            claim = ChallengeRewardClaim(
                user_id=test_user.id,
                challenge_id="complete_lessons",
                claim_date=claim_date,
                xp_reward=20,
                gems_reward=0,
            )
            try:
                async with session.begin_nested():
                    session.add(claim)
                    await session.flush()
                await session.commit()
                return True
            except IntegrityError:
                await session.rollback()
                return False

    results = await asyncio.gather(try_claim(), try_claim())

    assert sorted(results) == [False, True]

    async with make_session() as verify_session:
        count = await verify_session.execute(
            select(func.count()).select_from(ChallengeRewardClaim).where(
                ChallengeRewardClaim.user_id == test_user.id,
                ChallengeRewardClaim.challenge_id == "complete_lessons",
            )
        )
        assert count.scalar() == 1


@pytest.mark.asyncio
async def test_concurrent_leaderboard_entry_creation_yields_one_row(
    db_engine, test_user: User
):
    """Two requests racing to create this week's leaderboard entry for the
    same user must converge on a single row, not duplicate it."""
    make_session = _sessionmaker(db_engine)

    async def get_or_create():
        async with make_session() as session:
            return await LeaderboardCRUD.get_or_create_entry(session, test_user.id)

    entry_a, entry_b = await asyncio.gather(get_or_create(), get_or_create())

    assert entry_a.id == entry_b.id

    async with make_session() as verify_session:
        week_start, _ = LeaderboardCRUD.get_current_week_range()
        count = await verify_session.execute(
            select(func.count()).select_from(LeaderboardEntry).where(
                LeaderboardEntry.user_id == test_user.id,
                LeaderboardEntry.week_start == week_start,
            )
        )
        assert count.scalar() == 1
