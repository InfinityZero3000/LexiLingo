"""Tests for XPEventEngine — mocked DB, pure calculation logic."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.services.ranking_agent.xp_event import XPEventEngine


def _make_user_row(
    uid: uuid.UUID | None = None,
    username: str = "alice",
    email: str = "alice@x.com",
) -> tuple:
    return (uid or uuid.uuid4(), username, email)


class FakeDB:
    def __init__(self, rows: list[tuple]) -> None:
        self._rows = rows

    async def execute(self, *_args, **_kwargs):
        return MagicMock(all=lambda: self._rows)


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_xp_event_all_target_counts_all_active_users() -> None:
    rows = [
        _make_user_row(username="alice"),
        _make_user_row(username="bob"),
        _make_user_row(username="carol"),
    ]
    engine = XPEventEngine()
    result = await engine.calculate(
        FakeDB(rows),
        {"target": "all", "duration_hours": 24, "multiplier": 2.0, "name": "Test Boost"},
    )

    assert result["target_user_count"] == 3
    assert result["multiplier"] == 2.0
    assert result["duration_hours"] == 24
    assert result["event_name"] == "Test Boost"
    assert result["item_type"] == "double_xp"


@pytest.mark.asyncio
async def test_xp_event_sample_capped_at_ten() -> None:
    rows = [_make_user_row(username=f"user{i}") for i in range(15)]
    engine = XPEventEngine()
    result = await engine.calculate(
        FakeDB(rows),
        {"target": "all", "duration_hours": 24, "multiplier": 2.0, "name": "Big Boost"},
    )

    assert len(result["sample_users"]) == 10
    assert result["target_user_count"] == 15


@pytest.mark.asyncio
async def test_xp_event_estimated_xp_delta_formula() -> None:
    rows = [_make_user_row()]
    engine = XPEventEngine()
    result = await engine.calculate(
        FakeDB(rows),
        {"target": "all", "duration_hours": 48, "multiplier": 3.0, "name": "Triple"},
    )
    # 1 user * 50 * (3.0 - 1) = 100
    assert result["estimated_total_xp_delta"] == "+100 XP"


@pytest.mark.asyncio
async def test_xp_event_zero_users_produces_zero_delta() -> None:
    engine = XPEventEngine()
    result = await engine.calculate(
        FakeDB([]),
        {"target": "all", "duration_hours": 24, "multiplier": 2.0, "name": "Empty"},
    )

    assert result["target_user_count"] == 0
    assert result["sample_users"] == []
    assert result["estimated_total_xp_delta"] == "+0 XP"


@pytest.mark.asyncio
async def test_xp_event_expires_at_is_in_future() -> None:
    engine = XPEventEngine()
    result = await engine.calculate(
        FakeDB([]),
        {"target": "all", "duration_hours": 24, "multiplier": 2.0, "name": "N"},
    )
    expires_at = datetime.fromisoformat(result["expires_at"])
    assert expires_at.tzinfo is not None
    assert expires_at > datetime.now(UTC)


@pytest.mark.asyncio
async def test_xp_event_sample_uses_username_over_email_prefix() -> None:
    uid = uuid.uuid4()
    rows = [(uid, "tester", "tester@x.com")]
    engine = XPEventEngine()
    result = await engine.calculate(
        FakeDB(rows),
        {"target": "all", "duration_hours": 24, "multiplier": 2.0, "name": "N"},
    )

    assert result["sample_users"][0]["username"] == "tester"


@pytest.mark.asyncio
async def test_xp_event_sample_falls_back_to_email_prefix_when_username_null() -> None:
    uid = uuid.uuid4()
    rows = [(uid, None, "fallback@x.com")]
    engine = XPEventEngine()
    result = await engine.calculate(
        FakeDB(rows),
        {"target": "all", "duration_hours": 24, "multiplier": 2.0, "name": "N"},
    )

    assert result["sample_users"][0]["username"] == "fallback"


# ---------------------------------------------------------------------------
# Default config values
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_xp_event_defaults_when_config_empty() -> None:
    engine = XPEventEngine()
    result = await engine.calculate(FakeDB([]), {})

    assert result["multiplier"] == 2.0
    assert result["duration_hours"] == 24
    assert result["event_name"] == "XP Event"
    assert result["target"] == "all"
