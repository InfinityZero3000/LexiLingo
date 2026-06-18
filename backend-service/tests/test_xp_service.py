import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.services.xp_service import REPEAT_SENSITIVE_SOURCES, award_xp_transaction


def _result(*, scalar_one_or_none=None):
    result = MagicMock()
    result.scalar_one_or_none.return_value = scalar_one_or_none
    return result


def _make_user(user_id: uuid.UUID | None = None) -> SimpleNamespace:
    return SimpleNamespace(
        id=user_id or uuid.uuid4(),
        total_xp=0,
        numeric_level=1,
        level="A1",
        rank="bronze",
        rank_score=0,
        rank_level_score=0,
        rank_proficiency_score=0,
    )


def _make_db(*side_effects) -> MagicMock:
    db = MagicMock()
    db.execute = AsyncMock(side_effect=list(side_effects))
    db.add = MagicMock()
    db.commit = AsyncMock()
    return db


@pytest.mark.asyncio
async def test_award_locks_user_and_updates_weekly_leaderboard():
    user_id = uuid.uuid4()
    user = SimpleNamespace(
        id=user_id,
        total_xp=90,
        numeric_level=1,
        level="A1",
        rank="bronze",
        rank_score=0,
        rank_level_score=0,
        rank_proficiency_score=0,
    )
    daily = SimpleNamespace(xp_earned=5)
    leaderboard = SimpleNamespace(xp_earned=20, league="bronze")
    db = MagicMock()
    # With source_id provided, there are 5 db.execute calls:
    # 1. SELECT ... FOR UPDATE (lock user row)
    # 2. SELECT XPTransaction (duplicate check — returns None = no duplicate)
    # 3. UPDATE users
    # 4. SELECT DailyActivity
    # 5. SELECT LeaderboardEntry ... FOR UPDATE
    db.execute = AsyncMock(
        side_effect=[
            _result(scalar_one_or_none=user),
            _result(scalar_one_or_none=None),
            MagicMock(),
            _result(scalar_one_or_none=daily),
            _result(scalar_one_or_none=leaderboard),
        ]
    )
    db.add = MagicMock()
    db.commit = AsyncMock()

    result = await award_xp_transaction(
        db=db,
        user=user,
        source="lesson",
        base_xp=10,
        source_id="lesson-uuid-001",
        daily_xp_loader=AsyncMock(return_value=5),
        streak_loader=AsyncMock(return_value=0),
    )

    assert result.xp_awarded == 10
    assert user.total_xp == 100
    assert daily.xp_earned == 15
    assert leaderboard.xp_earned == 30
    assert leaderboard.league == user.rank
    assert db.execute.await_count == 5
    db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_award_creates_current_week_leaderboard_entry():
    user_id = uuid.uuid4()
    user = SimpleNamespace(
        id=user_id,
        total_xp=0,
        numeric_level=1,
        level="A1",
        rank="bronze",
        rank_score=0,
        rank_level_score=0,
        rank_proficiency_score=0,
    )
    db = MagicMock()
    # 5 execute calls: lock user, duplicate check (None), UPDATE users, daily (None), leaderboard (None)
    db.execute = AsyncMock(
        side_effect=[
            _result(scalar_one_or_none=user),
            _result(scalar_one_or_none=None),
            MagicMock(),
            _result(scalar_one_or_none=None),
            _result(scalar_one_or_none=None),
        ]
    )
    db.add = MagicMock()
    db.commit = AsyncMock()

    await award_xp_transaction(
        db=db,
        user=user,
        source="lesson",
        base_xp=10,
        source_id="lesson-uuid-002",
        daily_xp_loader=AsyncMock(return_value=0),
        streak_loader=AsyncMock(return_value=0),
    )

    leaderboard_entries = [
        call.args[0]
        for call in db.add.call_args_list
        if call.args[0].__class__.__name__ == "LeaderboardEntry"
    ]
    assert len(leaderboard_entries) == 1
    assert leaderboard_entries[0].xp_earned == 10
    assert leaderboard_entries[0].league == user.rank


# ── Task 5: source_id requirement for repeat-sensitive sources ────────────────

@pytest.mark.parametrize("source", sorted(REPEAT_SENSITIVE_SOURCES))
@pytest.mark.asyncio
async def test_repeat_sensitive_source_requires_source_id(source: str) -> None:
    """award_xp_transaction raises 422 when source_id is absent for repeat-sensitive sources."""
    user = _make_user()
    db = _make_db()

    with pytest.raises(HTTPException) as exc_info:
        await award_xp_transaction(
            db=db,
            user=user,
            source=source,
            base_xp=10,
            source_id=None,
            daily_xp_loader=AsyncMock(return_value=0),
            streak_loader=AsyncMock(return_value=0),
        )

    assert exc_info.value.status_code == 422
    assert "source_id" in exc_info.value.detail
    db.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_non_repeat_sensitive_source_allows_missing_source_id() -> None:
    """Sources like 'news' do not require source_id."""
    user = _make_user()
    db = _make_db(
        _result(scalar_one_or_none=user),
        MagicMock(),
        _result(scalar_one_or_none=None),
        _result(scalar_one_or_none=None),
    )

    result = await award_xp_transaction(
        db=db,
        user=user,
        source="news",
        base_xp=10,
        source_id=None,
        daily_xp_loader=AsyncMock(return_value=0),
        streak_loader=AsyncMock(return_value=0),
    )

    assert result.xp_awarded == 10


@pytest.mark.asyncio
async def test_repeat_sensitive_source_with_source_id_proceeds() -> None:
    """A repeat-sensitive source with source_id provided is accepted."""
    user = _make_user()
    # execute order: lock user, dup-check (None=no dup), UPDATE users, daily (None), leaderboard (None)
    db = _make_db(
        _result(scalar_one_or_none=user),
        _result(scalar_one_or_none=None),
        MagicMock(),
        _result(scalar_one_or_none=None),
        _result(scalar_one_or_none=None),
    )

    result = await award_xp_transaction(
        db=db,
        user=user,
        source="lesson",
        base_xp=10,
        source_id="lesson-uuid-003",
        daily_xp_loader=AsyncMock(return_value=0),
        streak_loader=AsyncMock(return_value=0),
    )

    assert result.xp_awarded == 10


@pytest.mark.asyncio
async def test_daily_challenge_requires_source_id() -> None:
    """daily_challenge is repeat-sensitive and must provide source_id."""
    user = _make_user()
    db = _make_db()

    with pytest.raises(HTTPException) as exc_info:
        await award_xp_transaction(
            db=db,
            user=user,
            source="daily_challenge",
            base_xp=50,
            source_id=None,
            daily_xp_loader=AsyncMock(return_value=0),
            streak_loader=AsyncMock(return_value=0),
        )

    assert exc_info.value.status_code == 422


@pytest.mark.asyncio
async def test_unsupported_source_raises_400() -> None:
    """An unknown source raises 400 before any source_id check."""
    user = _make_user()
    db = _make_db()

    with pytest.raises(HTTPException) as exc_info:
        await award_xp_transaction(
            db=db,
            user=user,
            source="cheat",
            base_xp=10,
            daily_xp_loader=AsyncMock(return_value=0),
            streak_loader=AsyncMock(return_value=0),
        )

    assert exc_info.value.status_code == 400
