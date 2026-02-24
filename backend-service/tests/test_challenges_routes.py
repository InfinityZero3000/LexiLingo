"""
Tests for Daily Challenges API Routes

Covers:
- GET  /challenges/daily                       — list with structure validation, auth required
- POST /challenges/daily/{challenge_id}/claim  — reward claim: success, already-claimed, not-completed, not-found
- POST /challenges/daily/bonus/claim           — all-challenges bonus: success, already-claimed, not-all-completed

All endpoints require authentication.
BASE = /api/v1/challenges
"""

import uuid
import pytest
from datetime import date
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


BASE = "/api/v1/challenges"
TEST_USER_ID = uuid.UUID("00000000-0000-0000-0000-000000000001")


# ---------------------------------------------------------------------------
# Helper: compute today's valid challenge ids for the test user
# ---------------------------------------------------------------------------

def _today_challenge_ids() -> tuple:
    """Return challenge ids generated for our test user today (deterministic)."""
    from app.routes.challenges import get_challenges_for_user
    challenges = get_challenges_for_user(TEST_USER_ID, date.today())
    return [c["id"] for c in challenges], challenges


# ---------------------------------------------------------------------------
# Fixture: authenticated client with mocked DB
# ---------------------------------------------------------------------------

@pytest.fixture
async def auth_client():
    """Authenticated HTTP client — DB queries return empty/zero results by default."""
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_user = MagicMock()
    mock_user.id = TEST_USER_ID
    mock_user.username = "testuser"
    mock_user.email = "test@example.com"
    mock_user.is_active = True
    mock_user.is_verified = True
    mock_user.level = "beginner"
    mock_user.total_xp = 0
    mock_user.numeric_level = 1
    mock_user.rank = "bronze"

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
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

    app.dependency_overrides.clear()


@pytest.fixture
async def no_auth_client():
    """Unauthenticated client — no dependency overrides."""
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


# ===========================================================================
# GET /challenges/daily
# ===========================================================================

class TestGetDailyChallenges:

    async def test_daily_returns_200(self, auth_client):
        """Authenticated request returns 200 OK."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        assert response.status_code == 200

    async def test_daily_response_success_flag(self, auth_client):
        """Response envelope has success=True."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        assert response.json()["success"] is True

    async def test_daily_response_has_challenges_list(self, auth_client):
        """Response data contains a 'challenges' list."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        data = response.json()["data"]
        assert "challenges" in data
        assert isinstance(data["challenges"], list)

    async def test_daily_challenges_list_is_non_empty(self, auth_client):
        """Daily challenges list contains at least one challenge."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        data = response.json()["data"]
        assert len(data["challenges"]) > 0

    async def test_daily_response_has_required_fields(self, auth_client):
        """Response data has date, total_completed, total_challenges, bonus_xp."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        data = response.json()["data"]
        for field in ("date", "total_completed", "total_challenges", "bonus_xp"):
            assert field in data, f"Missing field: {field}"

    async def test_daily_challenge_item_has_required_fields(self, auth_client):
        """Each challenge object has id, title, description, icon, category, target,
        current, xp_reward, is_completed, expires_at."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        challenge = response.json()["data"]["challenges"][0]
        required = ("id", "title", "description", "icon", "category",
                    "target", "current", "xp_reward", "is_completed", "expires_at")
        for field in required:
            assert field in challenge, f"Challenge missing field: {field}"

    async def test_daily_zero_progress_not_completed(self, auth_client):
        """With zero progress, challenges are not completed."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        challenges = response.json()["data"]["challenges"]
        assert all(not c["is_completed"] for c in challenges)

    async def test_daily_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated request is rejected."""
        response = await no_auth_client.get(f"{BASE}/daily")
        assert response.status_code in (401, 403)

    async def test_daily_total_challenges_matches_list_length(self, auth_client):
        """total_challenges in response equals length of challenges list."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.get(f"{BASE}/daily")
        data = response.json()["data"]
        assert data["total_challenges"] == len(data["challenges"])


# ===========================================================================
# POST /challenges/daily/{challenge_id}/claim
# ===========================================================================

class TestClaimChallengeReward:

    async def test_claim_nonexistent_challenge_returns_404(self, auth_client):
        """Claiming a challenge id that is not in today's set returns 404."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.post(
                f"{BASE}/daily/nonexistent_challenge_xyz/claim"
            )
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()

    async def test_claim_already_claimed_returns_400(self):
        """Attempting to claim a reward that was already claimed today returns 400."""
        from app.main import app
        from app.core.database import get_db
        from app.core.dependencies import get_current_user

        challenge_ids, _ = _today_challenge_ids()
        valid_challenge_id = challenge_ids[0]
        existing_claim = MagicMock()

        mock_user = MagicMock()
        mock_user.id = TEST_USER_ID

        async def mock_get_db():
            mock_result = MagicMock()
            mock_result.scalar.return_value = 0
            mock_result.scalar_one_or_none.return_value = existing_claim
            mock_result.scalars.return_value.all.return_value = []

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

        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(f"{BASE}/daily/{valid_challenge_id}/claim")

        app.dependency_overrides.clear()

        assert response.status_code == 400
        assert "already claimed" in response.json()["detail"].lower()

    async def test_claim_not_completed_returns_400(self, auth_client):
        """Claiming a reward for an incomplete challenge returns 400."""
        challenge_ids, _ = _today_challenge_ids()
        valid_challenge_id = challenge_ids[0]

        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.post(
                f"{BASE}/daily/{valid_challenge_id}/claim"
            )
        assert response.status_code == 400
        assert "Progress" in response.json()["detail"] or "not completed" in response.json()["detail"].lower()

    async def test_claim_success_returns_200(self):
        """Claiming a completed challenge returns 200 with xp_reward."""
        from app.main import app
        from app.core.database import get_db
        from app.core.dependencies import get_current_user

        challenge_ids, challenges = _today_challenge_ids()
        valid_challenge_id = challenge_ids[0]

        mock_user = MagicMock()
        mock_user.id = TEST_USER_ID
        mock_user.total_xp = 0
        mock_user.numeric_level = 1
        mock_user.level = "beginner"

        async def mock_get_db():
            mock_result = MagicMock()
            mock_result.scalar.return_value = 0
            mock_result.scalar_one_or_none.return_value = None   # not claimed yet
            mock_result.scalars.return_value.all.return_value = []

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

        mock_rank = MagicMock()
        mock_rank.rank.value = "bronze"

        with (
            patch("app.routes.challenges.calculate_challenge_progress", new=AsyncMock(return_value=999)),
            patch("app.services.item_effects_service.ItemEffectsService") as MockEffects,
            patch("app.services.level_service.calculate_numeric_level", return_value=1),
            patch("app.services.rank_service.calculate_rank", return_value=mock_rank),
            patch("app.services.check_achievements_for_user", new=AsyncMock()),
            patch("app.crud.gamification.WalletCRUD.add_gems", new=AsyncMock()),
        ):
            effects_instance = AsyncMock()
            effects_instance.get_xp_multiplier = AsyncMock(return_value=1.0)
            MockEffects.return_value = effects_instance

            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(f"{BASE}/daily/{valid_challenge_id}/claim")

        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "xp_reward" in data["data"]

    async def test_claim_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated claim request is rejected."""
        response = await no_auth_client.post(f"{BASE}/daily/complete_lessons/claim")
        assert response.status_code in (401, 403)


# ===========================================================================
# POST /challenges/daily/bonus/claim
# ===========================================================================

class TestClaimDailyBonus:

    async def test_bonus_claim_not_all_completed_returns_400(self, auth_client):
        """Claiming bonus when not all challenges are complete returns 400."""
        with patch(
            "app.routes.challenges.calculate_challenge_progress",
            new=AsyncMock(return_value=0),
        ):
            response = await auth_client.post(f"{BASE}/daily/bonus/claim")
        assert response.status_code == 400
        assert "Complete all challenges" in response.json()["detail"]

    async def test_bonus_claim_already_claimed_returns_400(self):
        """Claiming bonus twice on the same day returns 400."""
        from app.main import app
        from app.core.database import get_db
        from app.core.dependencies import get_current_user

        existing_claim = MagicMock()
        mock_user = MagicMock()
        mock_user.id = TEST_USER_ID

        async def mock_get_db():
            mock_result = MagicMock()
            mock_result.scalar.return_value = 0
            mock_result.scalar_one_or_none.return_value = existing_claim
            mock_result.scalars.return_value.all.return_value = []

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

        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(f"{BASE}/daily/bonus/claim")

        app.dependency_overrides.clear()

        assert response.status_code == 400
        assert "Bonus already claimed" in response.json()["detail"]

    async def test_bonus_claim_success_returns_200(self):
        """Claiming bonus after completing all challenges returns 200 with XP and gems."""
        from app.main import app
        from app.core.database import get_db
        from app.core.dependencies import get_current_user

        mock_user = MagicMock()
        mock_user.id = TEST_USER_ID
        mock_user.total_xp = 0
        mock_user.numeric_level = 1
        mock_user.level = "beginner"

        async def mock_get_db():
            mock_result = MagicMock()
            mock_result.scalar.return_value = 0
            mock_result.scalar_one_or_none.return_value = None
            mock_result.scalars.return_value.all.return_value = []

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

        mock_rank = MagicMock()
        mock_rank.rank.value = "bronze"

        with (
            patch("app.routes.challenges.calculate_challenge_progress", new=AsyncMock(return_value=999)),
            patch("app.services.item_effects_service.ItemEffectsService") as MockEffects,
            patch("app.services.level_service.calculate_numeric_level", return_value=1),
            patch("app.services.rank_service.calculate_rank", return_value=mock_rank),
            patch("app.crud.gamification.WalletCRUD.add_gems", new=AsyncMock()),
        ):
            effects_instance = AsyncMock()
            effects_instance.get_xp_multiplier = AsyncMock(return_value=1.0)
            MockEffects.return_value = effects_instance

            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(f"{BASE}/daily/bonus/claim")

        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "xp_reward" in data["data"]
        assert "gems_reward" in data["data"]

    async def test_bonus_claim_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated bonus claim is rejected."""
        response = await no_auth_client.post(f"{BASE}/daily/bonus/claim")
        assert response.status_code in (401, 403)
