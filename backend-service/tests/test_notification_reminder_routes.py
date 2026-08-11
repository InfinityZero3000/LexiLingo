"""Route coverage for persisted notifications and reminder preferences."""

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.main import app
from app.models.notification import Notification


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


@pytest.mark.asyncio
async def test_delete_notification_removes_owned_notification(
    async_client,
    db_session,
    auth_headers,
    test_user,
):
    notification = Notification(
        user_id=test_user.id,
        title="Old notification",
        body="Done",
        type="system",
    )
    db_session.add(notification)
    await db_session.commit()
    await db_session.refresh(notification)

    response = await async_client.delete(
        f"/api/v1/notifications/{notification.id}",
        headers=auth_headers,
    )

    assert response.status_code == 200
    assert await db_session.get(Notification, notification.id) is None


@pytest.mark.asyncio
async def test_delete_all_notifications_removes_owned_notifications(
    async_client,
    db_session,
    auth_headers,
    test_user,
):
    db_session.add_all(
        [
            Notification(user_id=test_user.id, title="One", body="Body", type="system"),
            Notification(user_id=test_user.id, title="Two", body="Body", type="system"),
        ]
    )
    await db_session.commit()

    response = await async_client.delete("/api/v1/notifications", headers=auth_headers)

    assert response.status_code == 200
    result = await db_session.execute(
        select(Notification).where(Notification.user_id == test_user.id)
    )
    assert result.scalars().all() == []
