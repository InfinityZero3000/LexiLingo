"""
Tests for XP API Routes — Phase 3

Tests cover:
- POST /xp/award          — anti-cheat, streak multiplier, daily cap, level-up
- GET  /xp/profile        — user XP/level/streak/history
- GET  /xp/leaderboard    — weekly top users
- Internal helper: _calculate_streak_multiplier
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport
import uuid


# ============================================================================
# Fixture: authenticated client with mocked DB and auth
# ============================================================================

@pytest.fixture
async def auth_client():
    """
    Async HTTP client with DB and auth mocked.
    XP endpoints require authentication and DB access.
    """
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_user = MagicMock()
    mock_user.id = uuid.UUID("12345678-1234-5678-1234-567812345678")
    mock_user.username = "testuser"
    mock_user.total_xp = 0
    mock_user.numeric_level = 1

    async def mock_get_db():
        mock_result = MagicMock()
        mock_result.scalar.return_value = 0
        mock_result.scalar_one_or_none.return_value = None
        mock_result.scalars.return_value.all.return_value = []
        mock_result.all.return_value = []

        mock_session = MagicMock()

        async def fake_execute(query):
            return mock_result

        mock_session.execute = fake_execute
        mock_session.add = MagicMock()
        mock_session.commit = AsyncMock()
        yield mock_session

    async def mock_get_current_user():
        return mock_user

    app.dependency_overrides[get_db] = mock_get_db
    app.dependency_overrides[get_current_user] = mock_get_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()


BASE = "/api/v1/xp"


# ============================================================================
# Unit Tests — _calculate_streak_multiplier
# ============================================================================

class TestCalculateStreakMultiplier:
    """Tests for the streak multiplier helper function."""

    def test_no_streak_returns_1x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(0) == 1.0

    def test_1_day_streak_returns_1x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(1) == 1.0

    def test_2_day_streak_returns_1x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(2) == 1.0

    def test_3_day_streak_returns_1_point_2x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(3) == 1.2

    def test_5_day_streak_returns_1_point_2x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(5) == 1.2

    def test_7_day_streak_returns_1_point_5x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(7) == 1.5

    def test_10_day_streak_returns_1_point_5x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(10) == 1.5

    def test_30_day_streak_returns_2x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(30) == 2.0

    def test_100_day_streak_returns_2x(self):
        from app.routes.xp import _calculate_streak_multiplier
        assert _calculate_streak_multiplier(100) == 2.0

    def test_multiplier_is_float(self):
        from app.routes.xp import _calculate_streak_multiplier
        result = _calculate_streak_multiplier(7)
        assert isinstance(result, float)

    def test_streak_thresholds_from_constants(self):
        from app.routes.xp import _calculate_streak_multiplier, STREAK_MULTIPLIERS
        for threshold, expected_mult in STREAK_MULTIPLIERS.items():
            assert _calculate_streak_multiplier(threshold) == expected_mult


# ============================================================================
# Unit Tests — Constants
# ============================================================================

class TestXPConstants:
    """Tests for XP system constants."""

    def test_daily_xp_cap_is_positive(self):
        from app.routes.xp import DAILY_XP_CAP
        assert DAILY_XP_CAP > 0
        assert DAILY_XP_CAP == 500

    def test_min_game_duration_is_positive(self):
        from app.routes.xp import MIN_GAME_DURATION
        assert MIN_GAME_DURATION > 0
        assert MIN_GAME_DURATION == 5

    def test_xp_source_caps_has_core_sources(self):
        from app.routes.xp import XP_SOURCE_CAPS
        for source in ["game", "news", "youtube"]:
            assert source in XP_SOURCE_CAPS
            assert XP_SOURCE_CAPS[source] > 0

    def test_game_source_cap_is_highest(self):
        from app.routes.xp import XP_SOURCE_CAPS
        game_cap = XP_SOURCE_CAPS.get("game", 0)
        news_cap = XP_SOURCE_CAPS.get("news", 0)
        assert game_cap > news_cap


# ============================================================================
# Route Tests — POST /xp/award
# ============================================================================

class TestAwardXP:
    """Tests for POST /xp/award endpoint."""

    @pytest.mark.asyncio
    async def test_awards_xp_successfully(self, auth_client: AsyncClient):
        """Basic XP award with mocked DB operations."""
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak, \
             patch("app.routes.xp.get_numeric_level_progress") as mock_level_info, \
             patch("app.routes.xp.check_numeric_level_up") as mock_level_up:

            mock_daily.return_value = 0
            mock_streak.return_value = 0
            mock_level_info.return_value = MagicMock(
                level_progress_percent=25.0,
                xp_for_next_level=75,
                current_xp_in_level=25,
                numeric_level=1,
            )
            mock_level_up.return_value = (False, 1, 1)

            response = await auth_client.post(
                f"{BASE}/award",
                json={
                    "source": "game",
                    "base_xp": 20,
                    "source_detail": "word_scramble",
                    "duration_seconds": 30,
                },
            )

        assert response.status_code == 200
        data = response.json()
        assert "xp_awarded" in data
        assert "base_xp" in data
        assert "multiplier" in data
        assert "new_total_xp" in data
        assert "daily_xp_today" in data
        assert "leveled_up" in data
        assert "streak_days" in data
        assert "message" in data

    @pytest.mark.asyncio
    async def test_rejects_game_duration_too_short(self, auth_client: AsyncClient):
        """Anti-cheat: game source with < MIN_GAME_DURATION seconds → 400."""
        response = await auth_client.post(
            f"{BASE}/award",
            json={
                "source": "game",
                "base_xp": 20,
                "duration_seconds": 3,  # Below MIN_GAME_DURATION=5
            },
        )
        assert response.status_code == 400
        assert "short" in response.json()["error"]["message"].lower() or \
               "cheat" in response.json()["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_requires_base_xp_minimum_1(self, auth_client: AsyncClient):
        """base_xp must be >= 1 (Pydantic validation)."""
        response = await auth_client.post(
            f"{BASE}/award",
            json={"source": "game", "base_xp": 0},
        )
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_requires_base_xp_maximum_200(self, auth_client: AsyncClient):
        """base_xp must be <= 200 (Pydantic validation)."""
        response = await auth_client.post(
            f"{BASE}/award",
            json={"source": "game", "base_xp": 201},
        )
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_non_game_source_no_duration_check(self, auth_client: AsyncClient):
        """Non-game sources skip duration anti-cheat check."""
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak, \
             patch("app.routes.xp.get_numeric_level_progress") as mock_level_info, \
             patch("app.routes.xp.check_numeric_level_up") as mock_level_up:

            mock_daily.return_value = 0
            mock_streak.return_value = 0
            mock_level_info.return_value = MagicMock(
                level_progress_percent=0.0,
                xp_for_next_level=100,
                current_xp_in_level=0,
                numeric_level=1,
            )
            mock_level_up.return_value = (False, 1, 1)

            # News source with very short duration — should NOT be rejected
            response = await auth_client.post(
                f"{BASE}/award",
                json={
                    "source": "news",
                    "base_xp": 15,
                    "duration_seconds": 2,  # Short but not a "game"
                },
            )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_streak_multiplier_applied(self, auth_client: AsyncClient):
        """7-day streak should produce 1.5x multiplier."""
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak, \
             patch("app.routes.xp.get_numeric_level_progress") as mock_level_info, \
             patch("app.routes.xp.check_numeric_level_up") as mock_level_up:

            mock_daily.return_value = 0
            mock_streak.return_value = 7  # 7-day streak → 1.5x
            mock_level_info.return_value = MagicMock(
                level_progress_percent=0.0,
                xp_for_next_level=100,
                current_xp_in_level=0,
                numeric_level=1,
            )
            mock_level_up.return_value = (False, 1, 1)

            response = await auth_client.post(
                f"{BASE}/award",
                json={"source": "game", "base_xp": 20, "duration_seconds": 30},
            )

        assert response.status_code == 200
        data = response.json()
        assert data["multiplier"] == 1.5
        assert data["xp_awarded"] == int(20 * 1.5)  # 30 XP

    @pytest.mark.asyncio
    async def test_daily_cap_returns_zero_xp(self, auth_client: AsyncClient):
        """When daily cap is reached, xp_awarded=0 and message about cap."""
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak:

            mock_daily.return_value = 500  # DAILY_XP_CAP=500 already reached
            mock_streak.return_value = 0

            response = await auth_client.post(
                f"{BASE}/award",
                json={"source": "game", "base_xp": 20, "duration_seconds": 30},
            )

        assert response.status_code == 200
        data = response.json()
        assert data["xp_awarded"] == 0
        assert data["daily_cap_remaining"] == 0
        assert "tomorrow" in data["message"].lower() or "cap" in data["message"].lower()

    @pytest.mark.asyncio
    async def test_level_up_is_reported(self, auth_client: AsyncClient):
        """When XP causes level up, leveled_up=True in response."""
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak, \
             patch("app.routes.xp.get_numeric_level_progress") as mock_level_info, \
             patch("app.routes.xp.check_numeric_level_up") as mock_level_up:

            mock_daily.return_value = 0
            mock_streak.return_value = 0
            mock_level_info.return_value = MagicMock(
                level_progress_percent=5.0,
                xp_for_next_level=95,
                current_xp_in_level=5,
                numeric_level=2,
            )
            mock_level_up.return_value = (True, 1, 2)  # Leveled up!

            response = await auth_client.post(
                f"{BASE}/award",
                json={"source": "lesson", "base_xp": 50, "duration_seconds": 60},
            )

        assert response.status_code == 200
        data = response.json()
        assert data["leveled_up"] is True
        assert data["new_level"] == 2
        assert "level" in data["message"].lower()


# ============================================================================
# Route Tests — GET /xp/profile
# ============================================================================

class TestXPProfile:
    """Tests for GET /xp/profile endpoint."""

    @pytest.mark.asyncio
    async def test_returns_profile_structure(self, auth_client: AsyncClient):
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak, \
             patch("app.routes.xp.get_numeric_level_progress") as mock_level_info:

            mock_daily.return_value = 50
            mock_streak.return_value = 3
            mock_level_info.return_value = MagicMock(
                numeric_level=1,
                level_progress_percent=10.0,
                xp_for_next_level=90,
                current_xp_in_level=10,
            )

            response = await auth_client.get(f"{BASE}/profile")

        assert response.status_code == 200
        data = response.json()
        required_fields = [
            "user_id", "total_xp", "numeric_level", "level_progress_percent",
            "xp_for_next_level", "current_xp_in_level",
            "daily_xp_today", "daily_cap_remaining",
            "streak_days", "best_streak", "recent_transactions",
        ]
        for field in required_fields:
            assert field in data, f"Missing field: {field}"

    @pytest.mark.asyncio
    async def test_daily_cap_remaining_calculated_correctly(self, auth_client: AsyncClient):
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak, \
             patch("app.routes.xp.get_numeric_level_progress") as mock_level_info:

            mock_daily.return_value = 200
            mock_streak.return_value = 0
            mock_level_info.return_value = MagicMock(
                numeric_level=1,
                level_progress_percent=0.0,
                xp_for_next_level=100,
                current_xp_in_level=0,
            )

            response = await auth_client.get(f"{BASE}/profile")

        assert response.status_code == 200
        data = response.json()
        # daily_cap_remaining should be 500 - 200 = 300
        assert data["daily_xp_today"] == 200
        assert data["daily_cap_remaining"] == 300

    @pytest.mark.asyncio
    async def test_recent_transactions_is_list(self, auth_client: AsyncClient):
        with patch("app.routes.xp._get_daily_xp", new_callable=AsyncMock) as mock_daily, \
             patch("app.routes.xp._get_streak_days", new_callable=AsyncMock) as mock_streak, \
             patch("app.routes.xp.get_numeric_level_progress") as mock_level_info:

            mock_daily.return_value = 0
            mock_streak.return_value = 0
            mock_level_info.return_value = MagicMock(
                numeric_level=1,
                level_progress_percent=0.0,
                xp_for_next_level=100,
                current_xp_in_level=0,
            )

            response = await auth_client.get(f"{BASE}/profile")

        assert response.status_code == 200
        assert isinstance(response.json()["recent_transactions"], list)


# ============================================================================
# Route Tests — GET /xp/leaderboard
# ============================================================================

class TestLeaderboard:
    """Tests for GET /xp/leaderboard endpoint."""

    @pytest.mark.asyncio
    async def test_returns_leaderboard_structure(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/leaderboard")
        assert response.status_code == 200
        data = response.json()
        assert "entries" in data
        assert "current_user" in data
        assert "week_start" in data
        assert isinstance(data["entries"], list)

    @pytest.mark.asyncio
    async def test_current_user_has_required_fields(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/leaderboard")
        assert response.status_code == 200
        current = response.json()["current_user"]
        assert "user_id" in current
        assert "username" in current
        assert "total_xp" in current
        assert "weekly_xp" in current
        assert "rank" in current

    @pytest.mark.asyncio
    async def test_limit_parameter_accepted(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/leaderboard?limit=10")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_entries_have_required_fields(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/leaderboard")
        assert response.status_code == 200
        for entry in response.json()["entries"]:
            assert "rank" in entry
            assert "user_id" in entry
            assert "username" in entry
            assert "total_xp" in entry
            assert "weekly_xp" in entry
