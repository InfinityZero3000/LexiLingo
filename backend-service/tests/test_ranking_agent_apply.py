import uuid
from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from sqlalchemy.dialects import sqlite

from app.services.ranking_agent import apply as ranking_apply
from app.services.ranking_agent.achievement_batch import AchievementBatchEngine


class _Result:
    def __init__(self, rows):
        self.rows = rows

    def all(self):
        return self.rows

    def scalars(self):
        return self


@pytest.mark.asyncio
async def test_achievement_apply_preloads_and_bulk_inserts(monkeypatch):
    existing_user_id = uuid.uuid4()
    new_user_id = uuid.uuid4()
    achievement = SimpleNamespace(id=uuid.uuid4(), slug="reader", xp_reward=50, gems_reward=10)

    class FakeDB:
        def __init__(self):
            self.calls = []
            self.params = []
            self.results = [
                _Result([achievement]),
                _Result([(existing_user_id, achievement.id)]),
                _Result([(new_user_id, achievement.id)]),
            ]

        async def execute(self, statement, params=None):
            self.calls.append(statement)
            self.params.append(params)
            return self.results[len(self.calls) - 1]

    async def eligible_users(_self, _db, _criteria):
        return [existing_user_id, new_user_id]

    reward_batch = AsyncMock()
    monkeypatch.setattr(
        AchievementBatchEngine,
        "_resolve_eligible_users",
        eligible_users,
    )
    monkeypatch.setattr(ranking_apply, "_grant_achievement_rewards", reward_batch)
    db = FakeDB()

    result = await ranking_apply._apply_achievement_batch(
        db,
        artifact={},
        config={"achievement_slugs": ["reader"], "criteria": {}},
    )

    assert result["granted_count"] == 1
    assert len(db.calls) == 3
    assert "ANY" not in str(db.calls[1].compile(dialect=sqlite.dialect()))
    assert "ON CONFLICT" in str(db.calls[2])
    assert len(db.params[2]) == 1
    reward_batch.assert_awaited_once()
    assert reward_batch.await_args.args[1] == [(new_user_id, achievement)]


@pytest.mark.asyncio
async def test_achievement_apply_does_not_reward_existing_pair(monkeypatch):
    user_id = uuid.uuid4()
    achievement = SimpleNamespace(id=uuid.uuid4(), slug="reader", xp_reward=50, gems_reward=10)

    class FakeDB:
        def __init__(self):
            self.results = [
                _Result([achievement]),
                _Result([(user_id, achievement.id)]),
            ]
            self.execute_count = 0

        async def execute(self, _statement, _params=None):
            result = self.results[self.execute_count]
            self.execute_count += 1
            return result

    async def eligible_users(_self, _db, _criteria):
        return [user_id]

    reward_batch = AsyncMock()
    monkeypatch.setattr(
        AchievementBatchEngine,
        "_resolve_eligible_users",
        eligible_users,
    )
    monkeypatch.setattr(ranking_apply, "_grant_achievement_rewards", reward_batch)
    db = FakeDB()

    result = await ranking_apply._apply_achievement_batch(
        db,
        artifact={},
        config={"achievement_slugs": ["reader"], "criteria": {}},
    )

    assert result["granted_count"] == 0
    assert db.execute_count == 2
    reward_batch.assert_awaited_once()
    assert reward_batch.await_args.args[1] == []


@pytest.mark.asyncio
async def test_achievement_apply_does_not_reward_conflict_loser(monkeypatch):
    user_id = uuid.uuid4()
    achievement = SimpleNamespace(id=uuid.uuid4(), slug="reader")

    class FakeDB:
        def __init__(self):
            self.results = [_Result([achievement]), _Result([]), _Result([])]
            self.execute_count = 0

        async def execute(self, _statement, _params=None):
            result = self.results[self.execute_count]
            self.execute_count += 1
            return result

    async def eligible_users(_self, _db, _criteria):
        return [user_id]

    reward_batch = AsyncMock()
    monkeypatch.setattr(
        AchievementBatchEngine,
        "_resolve_eligible_users",
        eligible_users,
    )
    monkeypatch.setattr(ranking_apply, "_grant_achievement_rewards", reward_batch)

    result = await ranking_apply._apply_achievement_batch(
        FakeDB(),
        artifact={},
        config={"achievement_slugs": ["reader"], "criteria": {}},
    )

    assert result["granted_count"] == 0
    assert reward_batch.await_args.args[1] == []


@pytest.mark.asyncio
async def test_achievement_rewards_batch_xp_and_gem_ledgers():
    user_id = uuid.uuid4()
    achievement = SimpleNamespace(
        id=uuid.uuid4(),
        slug="reader",
        name="Reader",
        xp_reward=50,
        gems_reward=10,
    )
    user = SimpleNamespace(
        id=user_id,
        total_xp=100,
        numeric_level=1,
        level="A1",
        rank="bronze",
        rank_score=0.0,
        rank_level_score=0.0,
        rank_proficiency_score=0.0,
    )
    wallet = SimpleNamespace(id=uuid.uuid4(), user_id=user_id, gems=5, total_gems_earned=5)

    class FakeDB:
        def __init__(self):
            self.scalar_results = [_Result([user]), _Result([wallet])]
            self.scalar_statements = []
            self.execute_calls = []
            self.added = []

        async def scalars(self, statement):
            self.scalar_statements.append(statement)
            return self.scalar_results.pop(0)

        async def execute(self, statement, _params=None):
            self.execute_calls.append(statement)
            if len(self.execute_calls) == 1:
                return _Result([(user_id, str(achievement.id))])
            return _Result([])

        def add_all(self, rows):
            self.added.extend(rows)

    db = FakeDB()
    await ranking_apply._grant_achievement_rewards(
        db,
        [(user_id, achievement)],
        datetime.now(UTC),
    )

    assert user.total_xp == 150
    assert wallet.gems == 15
    assert wallet.total_gems_earned == 15
    assert len(db.execute_calls) == 4
    assert "xp_transactions" in str(db.execute_calls[0])
    assert all(
        "ANY" not in str(statement.compile(dialect=sqlite.dialect()))
        for statement in db.scalar_statements
    )
    assert len(db.added) == 1
    assert db.added[0].reference_id == str(achievement.id)
