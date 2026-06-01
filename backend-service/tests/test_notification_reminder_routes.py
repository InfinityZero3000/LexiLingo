"""Route coverage for persisted notifications and reminder preferences."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/notifications",
        "/api/v1/users/me/reminder-preferences",
    ],
)
async def test_authenticated_notification_and_reminder_routes_are_mounted(path):
    """Mounted auth routes should reject anonymous calls instead of 404ing."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get(path)

    assert response.status_code == 401
