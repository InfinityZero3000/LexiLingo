from datetime import date
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.services import streak_service
from app.services.streak_service import update_user_streak


def _result(value=None):
    result = MagicMock()
    result.scalar_one_or_none.return_value = value
    return result


@pytest.mark.asyncio
async def test_update_user_streak_uses_utc_service_date(monkeypatch):
    fixed_today = date(2026, 6, 26)
    monkeypatch.setattr(streak_service, "_utc_today", lambda: fixed_today)
    monkeypatch.setattr(
        streak_service,
        "check_achievements_for_user",
        AsyncMock(return_value=[]),
    )
    monkeypatch.setattr(streak_service, "delete_cached", AsyncMock())

    db = MagicMock()
    db.execute = AsyncMock(side_effect=[_result(None), _result(None)])
    db.add = MagicMock()
    db.flush = AsyncMock()

    streak, increased, saved, achievements = await update_user_streak(
        db,
        uuid4(),
    )

    assert streak.last_activity_date == fixed_today
    assert streak.current_streak == 1
    assert increased is True
    assert saved is False
    assert achievements == []
