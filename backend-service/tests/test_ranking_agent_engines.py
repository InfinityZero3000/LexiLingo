"""Tests for LeagueResetEngine, XPEventEngine, and AchievementBatchEngine."""

import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.ranking_agent.league_reset import LeagueResetEngine, _week_range_for
from app.schemas.ranking_agent import (
    AchievementBatchConfig,
    LeagueResetConfig,
    RankingAgentJobCreate,
    XPEventConfig,
)


# ---------------------------------------------------------------------------
# Schema validation tests
# ---------------------------------------------------------------------------

def test_league_reset_config_default():
    cfg = LeagueResetConfig()
    assert cfg.job_type == "league_reset"
    assert cfg.week_start is None


def test_xp_event_config_all_target():
    cfg = XPEventConfig(name="Weekend Boost", multiplier=2.0, duration_hours=48, target="all")
    assert cfg.target == "all"


def test_xp_event_config_league_target():
    cfg = XPEventConfig(name="Gold Boost", multiplier=1.5, duration_hours=24, target="league:gold")
    assert cfg.target == "league:gold"


def test_xp_event_config_invalid_league():
    with pytest.raises(Exception, match="Unknown league"):
        XPEventConfig(name="x", multiplier=2.0, duration_hours=24, target="league:diamond")


def test_xp_event_config_invalid_cefr():
    with pytest.raises(Exception, match="Unknown CEFR level"):
        XPEventConfig(name="x", multiplier=2.0, duration_hours=24, target="cefr:Z1")


def test_achievement_batch_requires_slugs():
    with pytest.raises(Exception):
        AchievementBatchConfig(achievement_slugs=[])


def test_ranking_agent_job_create_invalid_type():
    with pytest.raises(Exception, match="Unknown job_type"):
        RankingAgentJobCreate(job_type="invalid_type", config={})


def test_ranking_agent_job_create_league_reset():
    payload = RankingAgentJobCreate(job_type="league_reset", config={})
    assert payload.job_type == "league_reset"


def test_ranking_agent_job_create_achievement_batch():
    payload = RankingAgentJobCreate(
        job_type="achievement_batch",
        config={"achievement_slugs": ["streak_30"]},
    )
    assert payload.job_type == "achievement_batch"


# ---------------------------------------------------------------------------
# LeagueResetEngine._week_range_for
# ---------------------------------------------------------------------------

def test_week_range_for_explicit_date():
    start, end = _week_range_for("2026-06-01")
    assert start.strftime("%Y-%m-%d") == "2026-06-01"
    # end is 7 days later
    delta = end - start
    assert delta.days == 7


def test_week_range_for_none_returns_last_monday():
    start, end = _week_range_for(None)
    assert start.weekday() == 0  # Monday
    delta = end - start
    assert delta.days == 7


# ---------------------------------------------------------------------------
# LeagueResetEngine.calculate (mocked DB)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_league_reset_engine_empty_db():
    engine = LeagueResetEngine(promotion_threshold=0.1, demotion_threshold=0.1)

    class FakeDB:
        async def execute(self, *_):
            return MagicMock(all=lambda: [])

    result = await engine.calculate(FakeDB(), {"week_start": "2026-06-01"})
    assert result["total_participants"] == 0
    assert result["promotions"] == []
    assert result["demotions"] == []


@pytest.mark.asyncio
async def test_league_reset_engine_promotes_top_user():
    engine = LeagueResetEngine(promotion_threshold=0.5, demotion_threshold=0.0)

    entry_high = SimpleNamespace(
        user_id=uuid.uuid4(), league="bronze", xp_earned=500,
        lessons_completed=10, id=uuid.uuid4(),
    )
    entry_low = SimpleNamespace(
        user_id=uuid.uuid4(), league="bronze", xp_earned=50,
        lessons_completed=1, id=uuid.uuid4(),
    )

    class FakeDB:
        async def execute(self, *_):
            return MagicMock(
                all=lambda: [
                    (entry_high, "alice", "alice@x.com"),
                    (entry_low, "bob", "bob@x.com"),
                ]
            )

    result = await engine.calculate(FakeDB(), {"week_start": "2026-06-01"})
    assert len(result["promotions"]) == 1
    assert result["promotions"][0]["username"] == "alice"
    assert result["promotions"][0]["to"] == "silver"
    assert result["league_summary"]["bronze"]["promoted"] == 1


@pytest.mark.asyncio
async def test_league_reset_engine_no_demotion_for_bronze():
    engine = LeagueResetEngine(promotion_threshold=0.0, demotion_threshold=0.9)

    entry = SimpleNamespace(
        user_id=uuid.uuid4(), league="bronze", xp_earned=10,
        lessons_completed=0, id=uuid.uuid4(),
    )

    class FakeDB:
        async def execute(self, *_):
            return MagicMock(all=lambda: [(entry, "user", "u@x.com")])

    result = await engine.calculate(FakeDB(), {"week_start": "2026-06-01"})
    assert result["demotions"] == []


@pytest.mark.asyncio
async def test_league_reset_engine_no_promotion_for_master():
    engine = LeagueResetEngine(promotion_threshold=0.9, demotion_threshold=0.0)

    entry = SimpleNamespace(
        user_id=uuid.uuid4(), league="master", xp_earned=9999,
        lessons_completed=50, id=uuid.uuid4(),
    )

    class FakeDB:
        async def execute(self, *_):
            return MagicMock(all=lambda: [(entry, "god", "g@x.com")])

    result = await engine.calculate(FakeDB(), {"week_start": "2026-06-01"})
    assert result["promotions"] == []
