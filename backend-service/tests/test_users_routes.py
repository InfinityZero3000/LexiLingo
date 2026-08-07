"""
Tests for User API Routes
/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/routes/users.py

Covers:
- GET  /api/v1/users/me              — get current user profile (auth)
- PUT  /api/v1/users/me              — update profile (auth)
- DELETE /api/v1/users/me            — delete account (auth, soft-delete)
- GET  /api/v1/users/{user_id}       — get user by ID (auth)
- GET  /api/v1/users/me/level        — level info (auth)
- GET  /api/v1/users/me/level-full   — full level info (auth)
- GET  /api/v1/users/me/stats        — user stats (auth)
- GET  /api/v1/users/me/weekly-activity — weekly activity (auth)
- POST /api/v1/users/me/xp           — award XP (auth)
"""

import pytest
import uuid
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport

BASE = "/api/v1/users"
OTHER_USER_ID = "550e8400-e29b-41d4-a716-446655440099"


# ============================================================================
# Fixtures
# ============================================================================

def _make_mock_user(user_id: str = "550e8400-e29b-41d4-a716-446655440001"):
    """Build a mock user with all typical fields filled."""
    user = MagicMock()
    user.id = uuid.UUID(user_id)
    user.username = "testuser"
    user.email = "test@example.com"
    user.display_name = "Test User"
    user.is_active = True
    user.is_verified = True
    user.level = "A1"
    user.cefr_level = "A1"
    user.goal = None
    user.interest = None
    user.native_language = "vi"
    user.target_language = "en"
    user.total_xp = 100
    user.numeric_level = 1
    user.rank = "bronze"
    user.avatar_url = None
    user.bio = None
    user.created_at = datetime.now(UTC)
    user.updated_at = datetime.now(UTC)
    user.last_login = None
    user.role_slug = "user"
    user.role_id = None
    user.role_level = 0
    user.is_admin = False
    user.is_super_admin = False
    return user


@pytest.fixture
async def auth_client():
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_result = MagicMock()
    mock_result.scalar.return_value = 0
    mock_result.scalar_one_or_none.return_value = None
    mock_result.scalars.return_value.all.return_value = []
    mock_result.all.return_value = []
    mock_result.first.return_value = None
    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    mock_session.execute = fake_execute
    mock_session.add = MagicMock()
    mock_session.commit = AsyncMock()
    mock_session.flush = AsyncMock()
    mock_session.refresh = AsyncMock()

    mock_user = _make_mock_user()

    async def mock_get_db():
        yield mock_session

    async def mock_get_current_user():
        return mock_user

    app.dependency_overrides[get_db] = mock_get_db
    app.dependency_overrides[get_current_user] = mock_get_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client, mock_session, mock_result, mock_user
    app.dependency_overrides.clear()


@pytest.fixture
async def no_auth_client():
    from app.main import app
    from app.core.database import get_db

    mock_result = MagicMock()
    mock_result.scalar.return_value = None
    mock_result.scalar_one_or_none.return_value = None
    mock_result.scalars.return_value.all.return_value = []
    mock_result.all.return_value = []
    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    mock_session.execute = fake_execute

    async def mock_get_db():
        yield mock_session

    app.dependency_overrides[get_db] = mock_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


# ============================================================================
# GET /api/v1/users/me  — Get current user profile
# ============================================================================

class TestGetCurrentUserProfile:
    """Tests for GET /api/v1/users/me."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/me")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.get(f"{BASE}/me")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_returns_user_email(self, auth_client):
        client, _, _, mock_user = auth_client
        response = await client.get(f"{BASE}/me")
        assert response.status_code == 200
        # Either JSON contains the email or the structure is accessible
        data = response.json()
        assert data.get("email") == mock_user.email

    @pytest.mark.asyncio
    async def test_returns_username(self, auth_client):
        client, _, _, mock_user = auth_client
        response = await client.get(f"{BASE}/me")
        data = response.json()
        assert data.get("username") == mock_user.username


# ============================================================================
# PUT /api/v1/users/me  — Update profile
# ============================================================================

class TestUpdateCurrentUserProfile:
    """Tests for PUT /api/v1/users/me."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.put(f"{BASE}/me", json={"display_name": "New Name"})
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_on_update(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.put(f"{BASE}/me", json={"display_name": "Updated Name"})
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_empty_body_returns_200(self, auth_client):
        """Empty update body is valid — no fields are changed."""
        client, _, _, _ = auth_client
        response = await client.put(f"{BASE}/me", json={})
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_update_native_language(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.put(f"{BASE}/me", json={"native_language": "fr"})
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_update_goal_and_interest_bumps_learner_state_epoch(self, auth_client):
        """Onboarding goal/interest must invalidate personalized AI caches —
        that's what bumping the shared learner-state epoch achieves."""
        client, _, _, mock_user = auth_client
        with patch("app.routes.users.bump_learner_state_epoch", new=AsyncMock()) as mock_bump:
            response = await client.put(
                f"{BASE}/me", json={"goal": "career", "interest": "technology"}
            )
        assert response.status_code == 200
        assert mock_user.goal == "career"
        assert mock_user.interest == "technology"
        mock_bump.assert_awaited_once()
        assert mock_bump.await_args.args[1] == mock_user.id

    @pytest.mark.asyncio
    async def test_update_without_goal_or_interest_skips_epoch_bump(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.routes.users.bump_learner_state_epoch", new=AsyncMock()) as mock_bump:
            response = await client.put(f"{BASE}/me", json={"display_name": "New Name"})
        assert response.status_code == 200
        mock_bump.assert_not_awaited()


# ============================================================================
# DELETE /api/v1/users/me  — Delete (soft) account
# ============================================================================

class TestDeleteCurrentUser:
    """Tests for DELETE /api/v1/users/me."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.delete(f"{BASE}/me")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_with_message(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.delete(f"{BASE}/me")
        assert response.status_code == 200
        assert "message" in response.json()

    @pytest.mark.asyncio
    async def test_deactivates_user(self, auth_client):
        client, _, _, mock_user = auth_client
        await client.delete(f"{BASE}/me")
        # The route sets is_active = False on mock_user
        assert mock_user.is_active is False

    @pytest.mark.asyncio
    async def test_response_message_contains_deactivated(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.delete(f"{BASE}/me")
        assert "deactivated" in response.json()["message"].lower()


# ============================================================================
# GET /api/v1/users/{user_id}  — Get user by ID
# ============================================================================

class TestGetUserById:
    """Tests for GET /api/v1/users/{user_id}."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/{OTHER_USER_ID}")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_user_not_found(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalar_one_or_none.return_value = None
        response = await client.get(f"{BASE}/{OTHER_USER_ID}")
        assert response.status_code == 404
        assert "not found" in response.json()["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_returns_user_when_found(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        other_user = _make_mock_user(OTHER_USER_ID)
        mock_result.scalar_one_or_none.return_value = other_user
        response = await client.get(f"{BASE}/{OTHER_USER_ID}")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_returned_user_has_correct_email(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        other_user = _make_mock_user(OTHER_USER_ID)
        other_user.email = "other@example.com"
        mock_result.scalar_one_or_none.return_value = other_user
        response = await client.get(f"{BASE}/{OTHER_USER_ID}")
        assert response.status_code == 200
        assert response.json().get("email") == "other@example.com"


# ============================================================================
# GET /api/v1/users/me/level  — Level info
# ============================================================================

class TestGetUserLevel:
    """Tests for GET /api/v1/users/me/level."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/me/level")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.get(f"{BASE}/me/level")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_data_key(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.get(f"{BASE}/me/level")
        assert "data" in response.json()


# ============================================================================
# GET /api/v1/users/me/level-full  — Full level info (numeric + CEFR)
# ============================================================================

class TestGetUserLevelFull:
    """Tests for GET /api/v1/users/me/level-full."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/me/level-full")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.get(f"{BASE}/me/level-full")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_uses_persisted_cefr_not_xp_derived(self, auth_client):
        client, _, _, mock_user = auth_client
        mock_user.level = "B1"
        mock_user.total_xp = 0  # XP-derived CEFR would be A1

        response = await client.get(f"{BASE}/me/level-full")
        assert response.status_code == 200

        data = response.json()["data"]
        assert data["cefr_level"] == "B1"
        assert data["proficiency_level"] == "B1"  # backward-compatible alias
        assert data["xp_derived_cefr_level"] == "A1"
        assert data["numeric_level"] == 1

    @pytest.mark.asyncio
    async def test_includes_split_cefr_fields(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.get(f"{BASE}/me/level-full")
        assert response.status_code == 200

        data = response.json()["data"]
        assert "cefr_level" in data
        assert "cefr_name" in data
        assert "cefr_progression_source" in data
        assert "xp_derived_cefr_level" in data
        assert "xp_derived_cefr_name" in data


# ============================================================================
# GET /api/v1/users/me/stats  — User stats
# ============================================================================

class TestGetUserStats:
    """Tests for GET /api/v1/users/me/stats."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/me/stats")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalar.return_value = 0
        mock_result.scalar_one_or_none.return_value = None
        response = await client.get(f"{BASE}/me/stats")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_stats_data(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalar.return_value = 0
        mock_result.scalar_one_or_none.return_value = None
        response = await client.get(f"{BASE}/me/stats")
        data = response.json()
        assert "data" in data


# ============================================================================
# GET /api/v1/users/me/weekly-activity  — Weekly activity
# ============================================================================

class TestGetWeeklyActivity:
    """Tests for GET /api/v1/users/me/weekly-activity."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/me/weekly-activity")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_row = MagicMock()
        mock_row.count = 0
        mock_row.xp = 0
        mock_row.time = 0
        mock_result.first.return_value = mock_row
        response = await client.get(f"{BASE}/me/weekly-activity")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_week_data(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_row = MagicMock()
        mock_row.count = 0
        mock_row.xp = 0
        mock_row.time = 0
        mock_result.first.return_value = mock_row
        response = await client.get(f"{BASE}/me/weekly-activity")
        data = response.json()["data"]
        assert "week_data" in data
        assert len(data["week_data"]) == 7


# ============================================================================
# POST /api/v1/users/me/xp  — Award XP
# ============================================================================

class TestAwardXP:
    """Tests for POST /api/v1/users/me/xp."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(f"{BASE}/me/xp", json={"amount": 50})
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_missing_amount_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(f"{BASE}/me/xp", json={})
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_awards_xp_successfully(self, auth_client):
        client, _, _, mock_user = auth_client
        mock_effects_service = AsyncMock()
        mock_effects_service.get_xp_multiplier = AsyncMock(return_value=1.0)

        with patch("app.services.item_effects_service.ItemEffectsService", return_value=mock_effects_service), \
             patch("app.services.level_service.LevelService.check_level_up", return_value=(False, None)):
            response = await client.post(f"{BASE}/me/xp", json={"amount": 50, "reason": "test"})

        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_xp_data(self, auth_client):
        client, _, _, mock_user = auth_client
        mock_effects_service = AsyncMock()
        mock_effects_service.get_xp_multiplier = AsyncMock(return_value=1.0)

        with patch("app.services.item_effects_service.ItemEffectsService", return_value=mock_effects_service), \
             patch("app.services.level_service.LevelService.check_level_up", return_value=(False, None)):
            response = await client.post(f"{BASE}/me/xp", json={"amount": 50, "reason": "test"})

        data = response.json()["data"]
        assert "total_xp" in data
        assert "xp_gained" in data
        assert "level_up" in data

    @pytest.mark.asyncio
    async def test_xp_boost_applied_with_multiplier(self, auth_client):
        """When a 2x boost is active, xp_gained should be double the base amount."""
        client, _, _, mock_user = auth_client
        mock_user.total_xp = 100

        mock_effects_service = AsyncMock()
        mock_effects_service.get_xp_multiplier = AsyncMock(return_value=2.0)

        with patch("app.services.item_effects_service.ItemEffectsService", return_value=mock_effects_service), \
             patch("app.services.level_service.LevelService.check_level_up", return_value=(False, None)):
            response = await client.post(f"{BASE}/me/xp", json={"amount": 50, "reason": "test"})

        assert response.status_code == 200
        data = response.json()["data"]
        # With 2x boost, 50 base XP -> 100 gained
        assert data["xp_gained"] == 100
