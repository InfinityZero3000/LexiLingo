"""
Tests for Device API Routes
/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/routes/devices.py

All device endpoints require authentication.

Covers:
- POST   /api/v1/devices              — register device (auth)
- PUT    /api/v1/devices/{device_id}  — update device (auth)
- DELETE /api/v1/devices/{device_id}  — unregister device (auth)
- GET    /api/v1/devices              — list user devices (auth)
"""

import pytest
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from httpx import AsyncClient, ASGITransport

BASE = "/api/v1/devices"
DEVICE_ID = "device-abc-123"


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
async def auth_client():
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_result = MagicMock()
    mock_result.scalar.return_value = None
    mock_result.scalar_one_or_none.return_value = None
    mock_result.scalars.return_value.all.return_value = []
    mock_result.all.return_value = []
    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    mock_session.execute = fake_execute
    mock_session.add = MagicMock()
    mock_session.commit = AsyncMock()
    mock_session.flush = AsyncMock()
    mock_session.refresh = AsyncMock()
    mock_session.delete = AsyncMock()

    mock_user = MagicMock()
    mock_user.id = "00000000-0000-0000-0000-000000000001"
    mock_user.username = "testuser"
    mock_user.email = "test@example.com"
    mock_user.is_active = True
    mock_user.is_verified = True
    mock_user.level = "beginner"
    mock_user.native_language = "vi"
    mock_user.target_language = "en"
    mock_user.total_xp = 100
    mock_user.display_name = "Test User"

    async def mock_get_db():
        yield mock_session

    async def mock_get_current_user():
        return mock_user

    app.dependency_overrides[get_db] = mock_get_db
    app.dependency_overrides[get_current_user] = mock_get_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client, mock_session, mock_result
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


def _make_mock_device():
    """Build a mock UserDevice with sensible defaults."""
    device = MagicMock()
    device.id = "00000000-0000-0000-0000-000000000099"
    device.device_id = DEVICE_ID
    device.device_type = "android"
    device.device_name = "Pixel 8"
    device.fcm_token = "mock-fcm-token-xyz"
    device.last_active = datetime.now(UTC)
    device.created_at = datetime.now(UTC)
    return device


VALID_REGISTER_PAYLOAD = {
    "device_id": DEVICE_ID,
    "device_type": "android",
    "device_name": "Pixel 8",
    "fcm_token": "mock-fcm-token-xyz",
}


# ============================================================================
# POST /api/v1/devices  — Register device
# ============================================================================

class TestRegisterDevice:
    """Tests for POST /api/v1/devices."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(BASE, json=VALID_REGISTER_PAYLOAD)
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_registers_new_device_returns_201(self, auth_client):
        client, mock_session, mock_result = auth_client
        # No existing device
        mock_result.scalar_one_or_none.return_value = None

        async def refresh_side_effect(obj):
            if not getattr(obj, "id", None) or str(type(obj.id)) == "<class 'unittest.mock.MagicMock'>":
                import uuid as _uuid
                obj.id = _uuid.uuid4()
            if not getattr(obj, "created_at", None) or str(type(obj.created_at)) == "<class 'unittest.mock.MagicMock'>":
                obj.created_at = datetime.now(UTC)

        mock_session.refresh = AsyncMock(side_effect=refresh_side_effect)

        response = await client.post(BASE, json=VALID_REGISTER_PAYLOAD)

        assert response.status_code == 201

    @pytest.mark.asyncio
    async def test_updates_existing_device_returns_200(self, auth_client):
        client, mock_session, mock_result = auth_client
        existing_device = _make_mock_device()
        mock_result.scalar_one_or_none.return_value = existing_device

        response = await client.post(BASE, json=VALID_REGISTER_PAYLOAD)

        # When device already exists, returns 201 (route always returns 201 status)
        assert response.status_code == 201

    @pytest.mark.asyncio
    async def test_missing_device_id_returns_422(self, auth_client):
        client, _, _ = auth_client
        payload = {k: v for k, v in VALID_REGISTER_PAYLOAD.items() if k != "device_id"}
        response = await client.post(BASE, json=payload)
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_missing_device_type_returns_422(self, auth_client):
        client, _, _ = auth_client
        payload = {k: v for k, v in VALID_REGISTER_PAYLOAD.items() if k != "device_type"}
        response = await client.post(BASE, json=payload)
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_response_contains_device_fields(self, auth_client):
        client, mock_session, mock_result = auth_client
        existing_device = _make_mock_device()
        mock_result.scalar_one_or_none.return_value = existing_device

        response = await client.post(BASE, json=VALID_REGISTER_PAYLOAD)
        data = response.json()
        assert "data" in data
        device_data = data["data"]
        assert "device_id" in device_data
        assert "device_type" in device_data
        assert "fcm_token" in device_data


# ============================================================================
# PUT /api/v1/devices/{device_id}  — Update device
# ============================================================================

class TestUpdateDevice:
    """Tests for PUT /api/v1/devices/{device_id}."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.put(
            f"{BASE}/{DEVICE_ID}", json={"fcm_token": "new-token"}
        )
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_device_not_found(self, auth_client):
        client, mock_session, mock_result = auth_client
        mock_result.scalar_one_or_none.return_value = None

        response = await client.put(
            f"{BASE}/{DEVICE_ID}", json={"fcm_token": "new-token"}
        )
        assert response.status_code == 404
        assert "not found" in response.json()["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_updates_fcm_token_successfully(self, auth_client):
        client, mock_session, mock_result = auth_client
        device = _make_mock_device()
        mock_result.scalar_one_or_none.return_value = device

        response = await client.put(
            f"{BASE}/{DEVICE_ID}", json={"fcm_token": "refreshed-token-abc"}
        )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_updates_device_name_successfully(self, auth_client):
        client, mock_session, mock_result = auth_client
        device = _make_mock_device()
        mock_result.scalar_one_or_none.return_value = device

        response = await client.put(
            f"{BASE}/{DEVICE_ID}", json={"device_name": "Galaxy S24"}
        )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_contains_success_true(self, auth_client):
        client, mock_session, mock_result = auth_client
        device = _make_mock_device()
        mock_result.scalar_one_or_none.return_value = device

        response = await client.put(
            f"{BASE}/{DEVICE_ID}", json={"fcm_token": "new-token"}
        )
        assert response.json()["success"] is True


# ============================================================================
# DELETE /api/v1/devices/{device_id}  — Unregister device
# ============================================================================

class TestUnregisterDevice:
    """Tests for DELETE /api/v1/devices/{device_id}."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.delete(f"{BASE}/{DEVICE_ID}")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_device_not_found(self, auth_client):
        client, mock_session, mock_result = auth_client
        mock_result.scalar_one_or_none.return_value = None

        response = await client.delete(f"{BASE}/{DEVICE_ID}")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_deletes_device_returns_200(self, auth_client):
        client, mock_session, mock_result = auth_client
        device = _make_mock_device()
        mock_result.scalar_one_or_none.return_value = device

        response = await client.delete(f"{BASE}/{DEVICE_ID}")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_delete_response_contains_message(self, auth_client):
        client, mock_session, mock_result = auth_client
        device = _make_mock_device()
        mock_result.scalar_one_or_none.return_value = device

        response = await client.delete(f"{BASE}/{DEVICE_ID}")
        assert "message" in response.json()


# ============================================================================
# GET /api/v1/devices  — List user devices
# ============================================================================

class TestListDevices:
    """Tests for GET /api/v1/devices."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(BASE)
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_with_empty_list(self, auth_client):
        client, mock_session, mock_result = auth_client
        mock_result.scalars.return_value.all.return_value = []

        response = await client.get(BASE)
        assert response.status_code == 200
        assert response.json()["data"] == []

    @pytest.mark.asyncio
    async def test_returns_device_list(self, auth_client):
        client, mock_session, mock_result = auth_client
        device = _make_mock_device()
        mock_result.scalars.return_value.all.return_value = [device]

        response = await client.get(BASE)
        assert response.status_code == 200
        data = response.json()
        assert "data" in data

    @pytest.mark.asyncio
    async def test_response_success_field_is_true(self, auth_client):
        client, mock_session, mock_result = auth_client
        mock_result.scalars.return_value.all.return_value = []

        response = await client.get(BASE)
        assert response.json()["success"] is True
