"""Tests for Phase 1 dashboard analytics API."""

import pytest
from datetime import datetime
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.models.rbac import Role
from app.models.user import User


@pytest.fixture
async def admin_token(db_session):
    """Create admin user and return JWT token."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        await client.post(
            "/api/v1/auth/register",
            json={
                "email": "test_admin@test.com",
                "username": "testadmin",
                "password": "testpass123",
                "display_name": "Test Admin",
            },
        )

        from sqlalchemy import select

        result = await db_session.execute(
            select(User).where(User.email == "test_admin@test.com")
        )
        user = result.scalar_one_or_none()
        if user is None:
            pytest.fail(
                "User 'test_admin@test.com' was not created by /auth/register. "
                "Check that the endpoint returns 200 and commits the user."
            )

        admin_role = await db_session.execute(select(Role).where(Role.slug == "admin"))
        role = admin_role.scalar_one_or_none()

        if role:
            user.role_id = role.id
            await db_session.commit()

        response = await client.post(
            "/api/v1/auth/login",
            json={"email": "test_admin@test.com", "password": "testpass123"},
        )

        data = response.json()
        return data["access_token"]


@pytest.mark.asyncio
class TestDashboardAnalytics:
    async def test_get_kpis(self, admin_token):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/kpis",
                headers={"Authorization": f"Bearer {admin_token}"},
            )

            assert response.status_code == 200
            data = response.json()
            assert "kpis" in data
            kpis = data["kpis"]
            assert "total_users" in kpis
            assert "active_users_7d" in kpis
            assert isinstance(kpis["total_users"], int)
            assert isinstance(kpis["active_users_7d"], int)

    async def test_get_user_growth(self, admin_token):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/user-growth?days=7",
                headers={"Authorization": f"Bearer {admin_token}"},
            )

            assert response.status_code == 200
            data = response.json()
            assert "data" in data
            assert isinstance(data["data"], list)

            if data["data"]:
                item = data["data"][0]
                assert "date" in item
                assert "new_users" in item
                assert "total_users" in item
                datetime.fromisoformat(item["date"])

    async def test_unauthorized_access(self):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/api/v1/admin/analytics/dashboard/kpis")
            assert response.status_code == 401


@pytest.mark.asyncio
class TestUserAnalytics:
    async def test_get_user_metrics(self, admin_token):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/user-metrics",
                headers={"Authorization": f"Bearer {admin_token}"},
            )
            assert response.status_code == 200
            data = response.json()
            assert "metrics" in data


@pytest.mark.asyncio
class TestContentAnalytics:
    async def test_get_content_performance(self, admin_token):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/content-performance",
                headers={"Authorization": f"Bearer {admin_token}"},
            )
            assert response.status_code == 200
            data = response.json()
            assert "courses" in data
            assert "lessons" in data

    async def test_get_vocabulary_effectiveness(self, admin_token):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/vocabulary-effectiveness",
                headers={"Authorization": f"Bearer {admin_token}"},
            )
            assert response.status_code == 200
            data = response.json()
            assert "total_words" in data
            assert "hardest_words" in data
            assert isinstance(data["hardest_words"], list)
