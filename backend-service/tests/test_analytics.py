"""Tests for Phase 1 dashboard analytics API."""

import pytest
from datetime import datetime
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.core.database import get_db
from app.core.security import create_access_token, get_password_hash
from app.models.rbac import Role
from app.models.user import User

from datetime import timezone
from app.models.course import Course, Lesson, Unit
from app.models.progress import LessonAttempt

@pytest.fixture
async def admin_token(db_session):
    """Create admin user directly in DB and return JWT token.

    Bypasses HTTP registration to avoid session-isolation issues between the
    test db_session and the app's own get_db connection pool.  Both share the
    same physical database in CI, so we override get_db to ensure the request
    handlers see the same session (and therefore the committed user + role).
    """
    admin_role = Role(
        name="Admin", slug="admin", level=1,
        description="Admin role", is_system=True, is_active=True,
    )
    db_session.add(admin_role)
    await db_session.commit()
    await db_session.refresh(admin_role)
    from tests.conftest import seed_admin_permissions
    await seed_admin_permissions(db_session)

    admin_user = User(
        email="test_admin@test.com",
        username="testadmin",
        hashed_password=get_password_hash("testpass123"),
        display_name="Test Admin",
        is_active=True,
        is_verified=True,
        role_id=admin_role.id,
    )
    db_session.add(admin_user)
    await db_session.commit()
    await db_session.refresh(admin_user)

    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db

    access_token = create_access_token(data={"sub": str(admin_user.id), "amr": "google"})
    yield access_token

    app.dependency_overrides.pop(get_db, None)


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

    async def test_content_performance_reports_measured_scores_and_times(
        self, async_client, admin_headers, db_session
    ):
        course = Course(title="Measured", language="en", level="A1", is_published=True)
        db_session.add(course)
        await db_session.flush()
        unit = Unit(course_id=course.id, title="U", order_index=0)
        db_session.add(unit)
        await db_session.flush()
        lesson = Lesson(course_id=course.id, unit_id=unit.id, title="L", order_index=0, lesson_type="lesson")
        learner = User(email="measured@example.com", username="measured", hashed_password="x")
        db_session.add_all([lesson, learner])
        await db_session.flush()
        now = datetime.now(timezone.utc)
        for score, passed, minutes, done in ((90, True, 4, now), (50, False, 2, now), (0, False, 0, None)):
            db_session.add(LessonAttempt(user_id=learner.id, lesson_id=lesson.id, score=score, passed=passed,
                                         time_spent_ms=minutes * 60_000, finished_at=done))
        await db_session.commit()

        data = (await async_client.get(
            "/api/v1/admin/analytics/content-performance", headers=admin_headers
        )).json()

        measured = next(c for c in data["courses"] if c["course_title"] == "Measured")
        assert (measured["avg_score"], measured["avg_time_minutes"]) == (70.0, 3.0)
        # The unfinished sitting counts for nothing.
        assert data["lessons"] == [{"lesson_id": str(lesson.id), "lesson_title": "L",
                                    "attempts": 2, "completions": 1, "avg_score": 70.0}]

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
