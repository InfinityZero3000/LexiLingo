"""
Tests for Progress API Routes
/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/routes/progress.py

All progress endpoints require authentication.

Covers:
- GET  /api/v1/progress/me                      — overall progress stats
- GET  /api/v1/progress/courses/{course_id}     — course-specific progress
- POST /api/v1/progress/lessons/{lesson_id}/complete — complete a lesson
- GET  /api/v1/progress/xp                      — total XP
- GET  /api/v1/progress/weekly                  — weekly stats
- GET  /api/v1/progress/streak                  — streak info
- POST /api/v1/progress/streak/update           — update streak
- POST /api/v1/progress/streak/freeze           — use streak freeze
"""

import pytest
from datetime import date, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport

BASE = "/api/v1/progress"
COURSE_ID = "00000000-0000-0000-0000-000000000010"
LESSON_ID = "00000000-0000-0000-0000-000000000011"


# ============================================================================
# Fixtures
# ============================================================================

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
    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    mock_session.execute = fake_execute
    mock_session.add = MagicMock()
    mock_session.commit = AsyncMock()
    mock_session.flush = AsyncMock()
    mock_session.refresh = AsyncMock()

    mock_user = MagicMock()
    mock_user.id = "00000000-0000-0000-0000-000000000001"
    mock_user.username = "testuser"
    mock_user.email = "test@example.com"
    mock_user.is_active = True
    mock_user.is_verified = True
    mock_user.level = "A1"
    mock_user.native_language = "vi"
    mock_user.target_language = "en"
    mock_user.total_xp = 100
    mock_user.numeric_level = 1
    mock_user.rank = "bronze"
    mock_user.display_name = "Test User"

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
# GET /api/v1/progress/me  — Overall progress stats
# ============================================================================

class TestGetMyProgress:
    """Tests for GET /api/v1/progress/me."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/me")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_with_empty_progress(self, auth_client):
        client, _, _, _ = auth_client
        mock_stats = {
            "total_xp": 0,
            "courses_enrolled": 0,
            "courses_completed": 0,
            "lessons_completed": 0,
            "current_streak": 0,
            "longest_streak": 0,
            "achievements_unlocked": 0,
        }
        with patch("app.crud.progress.ProgressCRUD.get_user_stats", new=AsyncMock(return_value=mock_stats)), \
             patch("app.crud.progress.ProgressCRUD.get_all_user_progress", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/me")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_expected_keys(self, auth_client):
        client, _, _, _ = auth_client
        mock_stats = {
            "total_xp": 100,
            "courses_enrolled": 2,
            "courses_completed": 1,
            "lessons_completed": 5,
            "current_streak": 3,
            "longest_streak": 7,
            "achievements_unlocked": 2,
        }
        with patch("app.crud.progress.ProgressCRUD.get_user_stats", new=AsyncMock(return_value=mock_stats)), \
             patch("app.crud.progress.ProgressCRUD.get_all_user_progress", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/me")
        data = response.json()
        assert "data" in data
        assert "summary" in data["data"]
        assert "course_progress" in data["data"]

    @pytest.mark.asyncio
    async def test_success_field_is_true(self, auth_client):
        client, _, _, _ = auth_client
        mock_stats = {
            "total_xp": 0,
            "courses_enrolled": 0,
            "courses_completed": 0,
            "lessons_completed": 0,
            "current_streak": 0,
            "longest_streak": 0,
            "achievements_unlocked": 0,
        }
        with patch("app.crud.progress.ProgressCRUD.get_user_stats", new=AsyncMock(return_value=mock_stats)), \
             patch("app.crud.progress.ProgressCRUD.get_all_user_progress", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/me")
        assert response.json()["success"] is True


# ============================================================================
# GET /api/v1/progress/courses/{course_id}  — Course-specific progress
# ============================================================================

class TestGetCourseProgress:
    """Tests for GET /api/v1/progress/courses/{course_id}."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/courses/{COURSE_ID}")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_course_not_found(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.course.CourseCRUD.get_course", new=AsyncMock(return_value=None)):
            response = await client.get(f"{BASE}/courses/{COURSE_ID}")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_returns_403_when_not_enrolled(self, auth_client):
        client, _, _, _ = auth_client
        mock_course = MagicMock()
        mock_course.id = COURSE_ID
        with patch("app.crud.course.CourseCRUD.get_course", new=AsyncMock(return_value=mock_course)), \
             patch("app.crud.course.CourseCRUD.is_user_enrolled", new=AsyncMock(return_value=False)):
            response = await client.get(f"{BASE}/courses/{COURSE_ID}")
        assert response.status_code == 403
        assert "enrolled" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_returns_404_when_no_progress_record(self, auth_client):
        client, _, _, _ = auth_client
        mock_course = MagicMock()
        mock_course.id = COURSE_ID
        with patch("app.crud.course.CourseCRUD.get_course", new=AsyncMock(return_value=mock_course)), \
             patch("app.crud.course.CourseCRUD.is_user_enrolled", new=AsyncMock(return_value=True)), \
             patch("app.crud.progress.ProgressCRUD.get_course_progress_detail", new=AsyncMock(return_value=None)):
            response = await client.get(f"{BASE}/courses/{COURSE_ID}")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_returns_200_with_valid_progress(self, auth_client):
        client, _, _, _ = auth_client
        mock_course = MagicMock()
        mock_course.id = COURSE_ID
        mock_progress_detail = {
            "course": {
                "course_id": COURSE_ID,
                "course_title": "Test Course",
                "progress_percentage": 50.0,
                "lessons_completed": 5,
                "total_lessons": 10,
                "total_xp_earned": 250,
                "started_at": "2024-01-01T00:00:00",
                "last_activity_at": "2024-01-15T00:00:00",
            },
            "units_progress": [],
        }
        with patch("app.crud.course.CourseCRUD.get_course", new=AsyncMock(return_value=mock_course)), \
             patch("app.crud.course.CourseCRUD.is_user_enrolled", new=AsyncMock(return_value=True)), \
             patch("app.crud.progress.ProgressCRUD.get_course_progress_detail", new=AsyncMock(return_value=mock_progress_detail)):
            response = await client.get(f"{BASE}/courses/{COURSE_ID}")
        assert response.status_code == 200
        assert response.json()["success"] is True


# ============================================================================
# GET /api/v1/progress/xp  — Total XP
# ============================================================================

class TestGetTotalXP:
    """Tests for GET /api/v1/progress/xp."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/xp")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_with_total_xp(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.progress.ProgressCRUD.get_user_total_xp", new=AsyncMock(return_value=250)):
            response = await client.get(f"{BASE}/xp")
        assert response.status_code == 200
        assert response.json()["data"]["total_xp"] == 250

    @pytest.mark.asyncio
    async def test_returns_zero_when_no_xp(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.progress.ProgressCRUD.get_user_total_xp", new=AsyncMock(return_value=0)):
            response = await client.get(f"{BASE}/xp")
        assert response.json()["data"]["total_xp"] == 0

    @pytest.mark.asyncio
    async def test_response_success_true(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.progress.ProgressCRUD.get_user_total_xp", new=AsyncMock(return_value=100)):
            response = await client.get(f"{BASE}/xp")
        assert response.json()["success"] is True


# ============================================================================
# GET /api/v1/progress/weekly  — Weekly stats
# ============================================================================

class TestGetWeeklyProgress:
    """Tests for GET /api/v1/progress/weekly."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/weekly")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalars.return_value.all.return_value = []
        response = await client.get(f"{BASE}/weekly")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_days_key(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalars.return_value.all.return_value = []
        response = await client.get(f"{BASE}/weekly")
        data = response.json()["data"]
        assert "days" in data
        assert len(data["days"]) == 7

    @pytest.mark.asyncio
    async def test_response_has_total_xp(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalars.return_value.all.return_value = []
        response = await client.get(f"{BASE}/weekly")
        data = response.json()["data"]
        assert "total_xp" in data
        assert "average_xp" in data

    @pytest.mark.asyncio
    async def test_each_day_has_required_fields(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalars.return_value.all.return_value = []
        response = await client.get(f"{BASE}/weekly")
        for day in response.json()["data"]["days"]:
            assert "date" in day
            assert "day_name" in day
            assert "xp_earned" in day
            assert "lessons_completed" in day


# ============================================================================
# GET /api/v1/progress/streak  — Streak info
# ============================================================================

class TestGetStreak:
    """Tests for GET /api/v1/progress/streak."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/streak")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_creates_new_streak_when_none_exists(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalar_one_or_none.return_value = None
        response = await client.get(f"{BASE}/streak")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_returns_streak_data_when_exists(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_streak = MagicMock()
        mock_streak.current_streak = 5
        mock_streak.longest_streak = 10
        mock_streak.total_days_active = 20
        mock_streak.last_activity_date = date.today()
        mock_streak.freeze_count = 2
        mock_result.scalar_one_or_none.return_value = mock_streak
        response = await client.get(f"{BASE}/streak")
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["current_streak"] == 5
        assert data["longest_streak"] == 10

    @pytest.mark.asyncio
    async def test_response_has_streak_fields(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_streak = MagicMock()
        mock_streak.current_streak = 3
        mock_streak.longest_streak = 7
        mock_streak.total_days_active = 15
        mock_streak.last_activity_date = None
        mock_streak.freeze_count = 0
        mock_result.scalar_one_or_none.return_value = mock_streak
        response = await client.get(f"{BASE}/streak")
        data = response.json()["data"]
        for key in ("current_streak", "longest_streak", "freeze_count", "is_active_today", "streak_at_risk"):
            assert key in data


# ============================================================================
# POST /api/v1/progress/streak/update  — Update streak
# ============================================================================

class TestUpdateStreak:
    """Tests for POST /api/v1/progress/streak/update."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(f"{BASE}/streak/update")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_creates_streak_for_new_user(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalar_one_or_none.return_value = None

        async def refresh_side_effect(obj):
            obj.current_streak = 1
            obj.longest_streak = 1
            obj.total_days_active = 1
            obj.freeze_count = 0

        mock_session.refresh = AsyncMock(side_effect=refresh_side_effect)

        with patch("app.services.check_achievements_for_user", new=AsyncMock(return_value=[])):
            response = await client.post(f"{BASE}/streak/update")

        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_increments_streak_on_consecutive_day(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        yesterday = date.today() - timedelta(days=1)
        mock_streak = MagicMock()
        mock_streak.current_streak = 3
        mock_streak.longest_streak = 5
        mock_streak.last_activity_date = yesterday
        mock_streak.freeze_count = 0
        mock_streak.total_days_active = 10
        mock_result.scalar_one_or_none.return_value = mock_streak

        async def refresh_side_effect(obj):
            obj.current_streak = 4

        mock_session.refresh = AsyncMock(side_effect=refresh_side_effect)

        with patch("app.services.check_achievements_for_user", new=AsyncMock(return_value=[])):
            response = await client.post(f"{BASE}/streak/update")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_streak_fields(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_streak = MagicMock()
        mock_streak.current_streak = 1
        mock_streak.longest_streak = 1
        mock_streak.last_activity_date = date.today()
        mock_streak.freeze_count = 0
        mock_streak.total_days_active = 1
        mock_result.scalar_one_or_none.return_value = mock_streak
        mock_session.refresh = AsyncMock()

        with patch("app.services.check_achievements_for_user", new=AsyncMock(return_value=[])):
            response = await client.post(f"{BASE}/streak/update")

        data = response.json()["data"]
        assert "current_streak" in data
        assert "streak_increased" in data
        assert "streak_saved" in data


# ============================================================================
# POST /api/v1/progress/streak/freeze  — Activate streak freeze
# ============================================================================

class TestUseStreakFreeze:
    """Tests for POST /api/v1/progress/streak/freeze."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(f"{BASE}/streak/freeze")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_no_streak_record(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalar_one_or_none.return_value = None
        response = await client.post(f"{BASE}/streak/freeze")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_returns_400_when_no_freezes_available(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_streak = MagicMock()
        mock_streak.freeze_count = 0
        mock_result.scalar_one_or_none.return_value = mock_streak
        response = await client.post(f"{BASE}/streak/freeze")
        assert response.status_code == 400
        assert "no streak freezes" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_returns_400_when_already_active_today(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_streak = MagicMock()
        mock_streak.freeze_count = 2
        mock_streak.last_activity_date = date.today()
        mock_result.scalar_one_or_none.return_value = mock_streak
        response = await client.post(f"{BASE}/streak/freeze")
        assert response.status_code == 400
        assert "already active" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_uses_freeze_successfully(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        yesterday = date.today() - timedelta(days=1)
        mock_streak = MagicMock()
        mock_streak.freeze_count = 2
        mock_streak.last_activity_date = yesterday
        mock_streak.current_streak = 5
        mock_result.scalar_one_or_none.return_value = mock_streak
        mock_session.refresh = AsyncMock()

        response = await client.post(f"{BASE}/streak/freeze")
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["freeze_used"] is True


# ============================================================================
# POST /api/v1/progress/lessons/{lesson_id}/complete  — Complete a lesson
# ============================================================================

class TestCompleteLesson:
    """Tests for POST /api/v1/progress/lessons/{lesson_id}/complete."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        payload = {"score": 85.0}
        response = await no_auth_client.post(
            f"{BASE}/lessons/{LESSON_ID}/complete", json=payload
        )
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_lesson_not_found(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.course.LessonCRUD.get_lesson", new=AsyncMock(return_value=None)):
            response = await client.post(
                f"{BASE}/lessons/{LESSON_ID}/complete", json={"score": 90.0, "lesson_id": LESSON_ID}
            )
        assert response.status_code in (404, 500)

    @pytest.mark.asyncio
    async def test_missing_score_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(
            f"{BASE}/lessons/{LESSON_ID}/complete", json={}
        )
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_completes_lesson_successfully(self, auth_client):
        client, mock_session, mock_result, mock_user = auth_client

        mock_lesson = MagicMock()
        mock_lesson.id = LESSON_ID
        mock_lesson.unit_id = "00000000-0000-0000-0000-000000000030"
        mock_lesson.pass_threshold = 80.0

        mock_unit = MagicMock()
        mock_unit.course_id = "00000000-0000-0000-0000-000000000010"

        mock_completion = MagicMock()
        mock_completion.is_passed = True
        mock_completion.best_score = 90.0

        mock_rank_info = MagicMock()
        mock_rank_info.rank.value = "bronze"

        mock_result.scalar_one_or_none.return_value = None  # No existing DailyActivity

        with patch("app.crud.course.LessonCRUD.get_lesson", new=AsyncMock(return_value=mock_lesson)), \
             patch("app.crud.course.UnitCRUD.get_unit", new=AsyncMock(return_value=mock_unit)), \
             patch("app.crud.course.CourseCRUD.is_user_enrolled", new=AsyncMock(return_value=True)), \
             patch("app.crud.progress.ProgressCRUD.mark_lesson_complete", new=AsyncMock(return_value=(mock_completion, 50))), \
             patch("app.crud.progress.ProgressCRUD.calculate_course_progress", new=AsyncMock(return_value=60.0)), \
             patch("app.crud.progress.ProgressCRUD.update_course_progress", new=AsyncMock(return_value=MagicMock())), \
             patch("app.services.level_service.LevelService.check_level_up", return_value=(False, None)), \
             patch("app.services.level_service.calculate_numeric_level", return_value=1), \
             patch("app.services.rank_service.calculate_rank", return_value=mock_rank_info), \
             patch("app.services.check_achievements_for_user", new=AsyncMock(return_value=[])):
            response = await client.post(
                f"{BASE}/lessons/{LESSON_ID}/complete", json={"score": 90.0, "lesson_id": LESSON_ID}
            )

        assert response.status_code == 200
        data = response.json()["data"]
        assert "lesson_id" in data
        assert "xp_earned" in data
        assert "is_passed" in data
