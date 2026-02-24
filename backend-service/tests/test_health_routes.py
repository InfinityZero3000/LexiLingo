"""
Tests for Health Check API Routes

Covers:
- GET /health  — returns 200 with status, message, version
- GET /ping    — returns 200 with pong message

Neither endpoint requires authentication or database access.
Note: health_router is mounted at root (no /api/v1 prefix).
"""

import pytest
from httpx import AsyncClient, ASGITransport


# ---------------------------------------------------------------------------
# Fixture: plain async client — no auth, no DB override needed
# ---------------------------------------------------------------------------

@pytest.fixture
async def client():
    """Async HTTP client wired directly to the FastAPI app."""
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


# ===========================================================================
# GET /health
# ===========================================================================

class TestHealthEndpoint:

    async def test_health_returns_200(self, client):
        """Health endpoint is reachable and returns 200 OK."""
        response = await client.get("/health")
        assert response.status_code == 200

    async def test_health_response_is_json(self, client):
        """Health endpoint returns valid JSON."""
        response = await client.get("/health")
        data = response.json()
        assert isinstance(data, dict)

    async def test_health_has_status_field(self, client):
        """Response includes a 'status' key."""
        response = await client.get("/health")
        assert "status" in response.json()

    async def test_health_status_is_healthy(self, client):
        """Status value is 'healthy'."""
        response = await client.get("/health")
        assert response.json()["status"] == "healthy"

    async def test_health_has_version_field(self, client):
        """Response includes a 'version' key."""
        response = await client.get("/health")
        assert "version" in response.json()

    async def test_health_has_message_field(self, client):
        """Response includes a human-readable 'message' key."""
        response = await client.get("/health")
        assert "message" in response.json()


# ===========================================================================
# GET /ping
# ===========================================================================

class TestPingEndpoint:

    async def test_ping_returns_200(self, client):
        """Ping endpoint is reachable and returns 200 OK."""
        response = await client.get("/ping")
        assert response.status_code == 200

    async def test_ping_response_is_json(self, client):
        """Ping endpoint returns valid JSON."""
        response = await client.get("/ping")
        assert response.status_code == 200
        assert isinstance(response.json(), dict)

    async def test_ping_has_message_field(self, client):
        """Ping response contains a 'message' key."""
        response = await client.get("/ping")
        assert "message" in response.json()

    async def test_ping_message_is_pong(self, client):
        """Ping 'message' value is 'pong'."""
        response = await client.get("/ping")
        assert response.json()["message"] == "pong"

    async def test_ping_content_type_is_json(self, client):
        """Content-Type header is application/json."""
        response = await client.get("/ping")
        assert "application/json" in response.headers.get("content-type", "")
