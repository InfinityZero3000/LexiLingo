"""
Tests for Proficiency Assessment API Routes

Covers:
- GET  /proficiency/profile             — get/create user proficiency profile
- POST /proficiency/record-exercises    — record exercise results and update scores
- GET  /proficiency/level-check         — level-up requirements check
- GET  /proficiency/level-thresholds    — all CEFR level threshold definitions (no auth needed)
- GET  /proficiency/history             — level change history
- GET  /proficiency/placement-test      — get 20-question CEFR placement test (auth, no DB)
- POST /proficiency/placement-test/submit — submit answers and receive assessed level

All endpoints except /level-thresholds require authentication.
BASE = /api/v1/proficiency
"""

import uuid
import pytest
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


BASE = "/api/v1/proficiency"
TEST_USER_ID = uuid.UUID("00000000-0000-0000-0000-000000000001")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_mock_profile() -> MagicMock:
    """Build a mock UserProficiencyProfile with sensible defaults."""
    p = MagicMock()
    p.id = uuid.UUID("00000000-0000-0000-0000-000000000010")
    p.user_id = TEST_USER_ID
    p.assessed_level = "A1"
    p.overall_score = 0.0
    p.total_xp = 0
    p.total_exercises_completed = 0
    p.total_correct_exercises = 0
    p.total_lessons_completed = 0
    p.last_assessment_at = None
    p.last_level_change_at = None
    # accuracy property — return 0.0 for zero division safety
    type(p).accuracy = property(lambda self: 0.0)
    return p


def _make_mock_level_check() -> MagicMock:
    """Build a mock LevelCheckResponse from ProficiencyService."""
    lc = MagicMock()
    lc.next_level = MagicMock()
    lc.next_level.value = "A2"
    lc.overall_progress = 0.0
    lc.qualifies_for_next = False
    lc.requirements = {}
    lc.blockers = ["No proficiency data yet."]
    return lc


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
async def auth_client():
    """Authenticated client — DB returns no profile by default."""
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_user = MagicMock()
    mock_user.id = TEST_USER_ID
    mock_user.username = "testuser"
    mock_user.email = "test@example.com"
    mock_user.level = "A1"
    mock_user.numeric_level = 1
    mock_user.xp = 0
    mock_user.total_xp = 0
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

        async def fake_refresh(obj):
            # Ensure required integer attrs are 0 (not None) on newly-created models
            for attr in (
                "total_exercises_completed",
                "total_correct_exercises",
                "total_lessons_completed",
                "total_xp",
            ):
                if getattr(obj, attr, None) is None:
                    setattr(obj, attr, 0)
            if getattr(obj, "id", None) is None:
                obj.id = uuid.uuid4()
            if getattr(obj, "overall_score", None) is None:
                obj.overall_score = 0.0
            if getattr(obj, "assessed_level", None) is None:
                obj.assessed_level = "A1"

        mock_session.execute = fake_execute
        mock_session.add = MagicMock()
        mock_session.commit = AsyncMock()
        mock_session.refresh = AsyncMock(side_effect=fake_refresh)
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
async def auth_client_with_profile():
    """Authenticated client where DB returns an existing proficiency profile."""
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_user = MagicMock()
    mock_user.id = TEST_USER_ID
    mock_user.username = "testuser"
    mock_user.email = "test@example.com"
    mock_user.level = "A1"
    mock_user.numeric_level = 1
    mock_user.xp = 0
    mock_user.total_xp = 0

    mock_profile = _make_mock_profile()

    async def mock_get_db():
        mock_result = MagicMock()
        mock_result.scalar.return_value = 0
        mock_result.scalar_one_or_none.return_value = mock_profile
        mock_result.scalars.return_value.all.return_value = []

        mock_session = MagicMock()

        async def fake_execute(query):
            return mock_result

        mock_session.execute = fake_execute
        mock_session.add = MagicMock()
        mock_session.commit = AsyncMock()
        mock_session.refresh = AsyncMock()
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
    """Unauthenticated client with no overrides."""
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


# ===========================================================================
# GET /proficiency/profile
# ===========================================================================

class TestGetProficiencyProfile:

    async def test_profile_returns_200(self, auth_client):
        """Authenticated request returns 200 OK."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client.get(f"{BASE}/profile")
        assert response.status_code == 200

    async def test_profile_response_has_user_id(self, auth_client):
        """Response dict contains 'user_id' key."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client.get(f"{BASE}/profile")
        assert "user_id" in response.json()

    async def test_profile_response_has_assessed_level(self, auth_client):
        """Response includes 'assessed_level' field."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client.get(f"{BASE}/profile")
        assert "assessed_level" in response.json()

    async def test_profile_response_has_skills_dict(self, auth_client):
        """Response includes 'skills' dictionary."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client.get(f"{BASE}/profile")
        data = response.json()
        assert "skills" in data
        assert isinstance(data["skills"], dict)

    async def test_profile_response_has_statistics(self, auth_client):
        """Response includes 'statistics' section."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client.get(f"{BASE}/profile")
        assert "statistics" in response.json()

    async def test_profile_response_has_next_level(self, auth_client):
        """Response includes 'next_level' object."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client.get(f"{BASE}/profile")
        assert "next_level" in response.json()

    async def test_profile_existing_user(self, auth_client_with_profile):
        """Profile endpoint works correctly when a profile already exists in DB."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client_with_profile.get(f"{BASE}/profile")
        assert response.status_code == 200

    async def test_profile_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated request is rejected."""
        response = await no_auth_client.get(f"{BASE}/profile")
        assert response.status_code in (401, 403)


# ===========================================================================
# POST /proficiency/record-exercises
# ===========================================================================

class TestRecordExercises:

    def _exercise_payload(self) -> list:
        return [
            {
                "exercise_type": "multiple_choice",
                "skill": "vocabulary",
                "difficulty_level": "A1",
                "is_correct": True,
                "score": 100.0,
                "time_spent_seconds": 30,
            }
        ]

    async def test_record_exercises_returns_200(self, auth_client):
        """Submitting a valid exercise result list returns 200."""
        mock_lc = _make_mock_level_check()
        mock_rank = MagicMock()
        mock_rank.rank.value = "bronze"

        with (
            patch(
                "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
                return_value=mock_lc,
            ),
            patch(
                "app.routes.proficiency.ProficiencyService.calculate_skill_score",
                return_value=(50.0, 0.8),
            ),
            patch(
                "app.routes.proficiency.ProficiencyService.calculate_overall_level",
                return_value=(MagicMock(value="A1"), 0.1),
            ),
            patch(
                "app.routes.proficiency.ProficiencyService._calculate_xp_from_exercises",
                return_value=10,
            ),
            patch("app.routes.proficiency.ProficiencyService.get_level_index", return_value=0),
        ):
            response = await auth_client.post(
                f"{BASE}/record-exercises",
                json=self._exercise_payload(),
            )
        assert response.status_code == 200

    async def test_record_exercises_response_has_exercises_recorded(self, auth_client):
        """Response contains 'exercises_recorded' field matching submission size."""
        with (
            patch(
                "app.routes.proficiency.ProficiencyService.calculate_skill_score",
                return_value=(50.0, 0.8),
            ),
            patch(
                "app.routes.proficiency.ProficiencyService.calculate_overall_level",
                return_value=(MagicMock(value="A1"), 0.1),
            ),
            patch(
                "app.routes.proficiency.ProficiencyService._calculate_xp_from_exercises",
                return_value=10,
            ),
            patch("app.routes.proficiency.ProficiencyService.get_level_index", return_value=0),
        ):
            response = await auth_client.post(
                f"{BASE}/record-exercises",
                json=self._exercise_payload(),
            )
        assert response.status_code == 200
        assert response.json()["exercises_recorded"] == 1

    async def test_record_exercises_returns_xp_earned(self, auth_client):
        """Response includes 'xp_earned' field."""
        with (
            patch(
                "app.routes.proficiency.ProficiencyService.calculate_skill_score",
                return_value=(50.0, 0.8),
            ),
            patch(
                "app.routes.proficiency.ProficiencyService.calculate_overall_level",
                return_value=(MagicMock(value="A1"), 0.1),
            ),
            patch(
                "app.routes.proficiency.ProficiencyService._calculate_xp_from_exercises",
                return_value=15,
            ),
            patch("app.routes.proficiency.ProficiencyService.get_level_index", return_value=0),
        ):
            response = await auth_client.post(
                f"{BASE}/record-exercises",
                json=self._exercise_payload(),
            )
        assert response.status_code == 200
        assert "xp_earned" in response.json()

    async def test_record_exercises_empty_list_returns_200(self, auth_client):
        """Empty exercise list is accepted and returns 200."""
        with (
            patch(
                "app.routes.proficiency.ProficiencyService.calculate_overall_level",
                return_value=(MagicMock(value="A1"), 0.0),
            ),
            patch(
                "app.routes.proficiency.ProficiencyService._calculate_xp_from_exercises",
                return_value=0,
            ),
            patch("app.routes.proficiency.ProficiencyService.get_level_index", return_value=0),
        ):
            response = await auth_client.post(
                f"{BASE}/record-exercises",
                json=[],
            )
        assert response.status_code == 200

    async def test_record_exercises_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated request is rejected."""
        response = await no_auth_client.post(
            f"{BASE}/record-exercises", json=[]
        )
        assert response.status_code in (401, 403)


# ===========================================================================
# GET /proficiency/level-check
# ===========================================================================

class TestLevelCheck:

    async def test_level_check_returns_200(self, auth_client):
        """Level-check endpoint returns 200 OK."""
        response = await auth_client.get(f"{BASE}/level-check")
        assert response.status_code == 200

    async def test_level_check_no_profile_returns_defaults(self, auth_client):
        """When no profile exists, response contains sensible A1 defaults."""
        response = await auth_client.get(f"{BASE}/level-check")
        data = response.json()
        assert data["current_level"] == "A1"
        assert "qualifies_for_next" in data

    async def test_level_check_has_required_fields(self, auth_client):
        """Response includes current_level, next_level, overall_progress, blockers."""
        response = await auth_client.get(f"{BASE}/level-check")
        data = response.json()
        for field in ("current_level", "qualifies_for_next", "requirements", "blockers"):
            assert field in data, f"Missing field: {field}"

    async def test_level_check_with_existing_profile(self, auth_client_with_profile):
        """Level-check works when a profile exists in DB."""
        mock_lc = _make_mock_level_check()
        with patch(
            "app.routes.proficiency.ProficiencyService.get_level_requirements_check",
            return_value=mock_lc,
        ):
            response = await auth_client_with_profile.get(f"{BASE}/level-check")
        assert response.status_code == 200

    async def test_level_check_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated request is rejected."""
        response = await no_auth_client.get(f"{BASE}/level-check")
        assert response.status_code in (401, 403)


# ===========================================================================
# GET /proficiency/level-thresholds
# ===========================================================================

class TestLevelThresholds:

    async def test_level_thresholds_returns_200(self, no_auth_client):
        """No auth required — returns 200 OK."""
        response = await no_auth_client.get(f"{BASE}/level-thresholds")
        assert response.status_code == 200

    async def test_level_thresholds_has_levels_key(self, no_auth_client):
        """Response contains 'levels' dictionary."""
        response = await no_auth_client.get(f"{BASE}/level-thresholds")
        data = response.json()
        assert "levels" in data
        assert isinstance(data["levels"], dict)

    async def test_level_thresholds_contains_all_cefr_levels(self, no_auth_client):
        """All six CEFR levels are present in the response."""
        response = await no_auth_client.get(f"{BASE}/level-thresholds")
        levels = response.json()["levels"]
        for cefr in ("A1", "A2", "B1", "B2", "C1", "C2"):
            assert cefr in levels, f"Missing CEFR level: {cefr}"

    async def test_level_thresholds_has_skill_weights(self, no_auth_client):
        """Response includes 'skill_weights' section."""
        response = await no_auth_client.get(f"{BASE}/level-thresholds")
        assert "skill_weights" in response.json()

    async def test_level_threshold_a2_has_required_fields(self, no_auth_client):
        """A2 threshold contains expected measurement fields."""
        response = await no_auth_client.get(f"{BASE}/level-thresholds")
        a2 = response.json()["levels"]["A2"]
        for field in (
            "min_vocabulary_score",
            "min_grammar_score",
            "min_overall_score",
            "min_exercises_completed",
            "min_accuracy",
        ):
            assert field in a2, f"A2 threshold missing field: {field}"


# ===========================================================================
# GET /proficiency/history
# ===========================================================================

class TestProficiencyHistory:

    async def test_history_returns_200(self, auth_client):
        """Authenticated request returns 200 OK."""
        response = await auth_client.get(f"{BASE}/history")
        assert response.status_code == 200

    async def test_history_no_profile_returns_empty_list(self, auth_client):
        """No profile means empty history list."""
        response = await auth_client.get(f"{BASE}/history")
        data = response.json()
        assert data == {"history": []}

    async def test_history_with_existing_profile_has_history_key(self, auth_client_with_profile):
        """With a profile present, response has 'history' list."""
        response = await auth_client_with_profile.get(f"{BASE}/history")
        assert response.status_code == 200
        assert "history" in response.json()

    async def test_history_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated request is rejected."""
        response = await no_auth_client.get(f"{BASE}/history")
        assert response.status_code in (401, 403)


# ===========================================================================
# GET /proficiency/placement-test
# ===========================================================================

class TestGetPlacementTest:

    async def test_placement_test_returns_200(self, auth_client):
        """Authenticated request returns 200 OK."""
        response = await auth_client.get(f"{BASE}/placement-test")
        assert response.status_code == 200

    async def test_placement_test_has_questions(self, auth_client):
        """Response contains 'questions' list."""
        response = await auth_client.get(f"{BASE}/placement-test")
        data = response.json()
        assert "questions" in data
        assert isinstance(data["questions"], list)

    async def test_placement_test_has_20_questions(self, auth_client):
        """Test contains exactly 20 questions."""
        response = await auth_client.get(f"{BASE}/placement-test")
        assert len(response.json()["questions"]) == 20

    async def test_placement_test_has_total_questions_field(self, auth_client):
        """Response includes 'total_questions' and 'max_score' fields."""
        response = await auth_client.get(f"{BASE}/placement-test")
        data = response.json()
        assert "total_questions" in data
        assert "max_score" in data

    async def test_placement_test_question_has_required_fields(self, auth_client):
        """Each question has id, level, points, skill, question, options fields."""
        response = await auth_client.get(f"{BASE}/placement-test")
        q = response.json()["questions"][0]
        for field in ("id", "level", "points", "skill", "question", "options"):
            assert field in q, f"Question missing field: {field}"

    async def test_placement_test_no_correct_answer_exposed(self, auth_client):
        """Questions must NOT expose the 'correct' answer index."""
        response = await auth_client.get(f"{BASE}/placement-test")
        for q in response.json()["questions"]:
            assert "correct" not in q

    async def test_placement_test_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated request is rejected."""
        response = await no_auth_client.get(f"{BASE}/placement-test")
        assert response.status_code in (401, 403)


# ===========================================================================
# POST /proficiency/placement-test/submit
# ===========================================================================

class TestSubmitPlacementTest:

    def _all_correct_answers(self) -> list:
        """Build the correct answer for every placement question."""
        from app.routes.proficiency import PLACEMENT_QUESTIONS
        return [
            {"question_id": q["id"], "selected_option": q["correct"]}
            for q in PLACEMENT_QUESTIONS
        ]

    def _all_wrong_answers(self) -> list:
        """Build clearly wrong answers for every placement question."""
        from app.routes.proficiency import PLACEMENT_QUESTIONS
        return [
            {"question_id": q["id"], "selected_option": (q["correct"] + 1) % 4}
            for q in PLACEMENT_QUESTIONS
        ]

    async def test_submit_returns_200(self, auth_client):
        """Submitting a placement test returns 200 OK."""
        mock_rank = MagicMock()
        mock_rank.rank.value = "bronze"
        mock_rank.name = "Bronze I"
        with patch("app.routes.proficiency.calculate_rank", return_value=mock_rank):
            response = await auth_client.post(
                f"{BASE}/placement-test/submit",
                json={"answers": self._all_correct_answers()},
            )
        assert response.status_code == 200

    async def test_submit_all_correct_returns_high_level(self, auth_client):
        """All correct answers should yield a high CEFR level (B2 or above)."""
        mock_rank = MagicMock()
        mock_rank.rank.value = "gold"
        mock_rank.name = "Gold I"
        with patch("app.routes.proficiency.calculate_rank", return_value=mock_rank):
            response = await auth_client.post(
                f"{BASE}/placement-test/submit",
                json={"answers": self._all_correct_answers()},
            )
        data = response.json()
        assert data["assessed_level"] in ("B2", "C1", "C2")

    async def test_submit_all_wrong_answers_returns_a1(self, auth_client):
        """All incorrect answers should yield A1 level."""
        mock_rank = MagicMock()
        mock_rank.rank.value = "bronze"
        mock_rank.name = "Bronze I"
        with patch("app.routes.proficiency.calculate_rank", return_value=mock_rank):
            response = await auth_client.post(
                f"{BASE}/placement-test/submit",
                json={"answers": self._all_wrong_answers()},
            )
        data = response.json()
        assert data["assessed_level"] == "A1"

    async def test_submit_response_has_required_fields(self, auth_client):
        """Response carries assessed_level, total_score, max_score, correct_count, details."""
        mock_rank = MagicMock()
        mock_rank.rank.value = "bronze"
        mock_rank.name = "Bronze I"
        with patch("app.routes.proficiency.calculate_rank", return_value=mock_rank):
            response = await auth_client.post(
                f"{BASE}/placement-test/submit",
                json={"answers": self._all_wrong_answers()},
            )
        data = response.json()
        for field in ("assessed_level", "total_score", "max_score", "correct_count", "details"):
            assert field in data, f"Missing field: {field}"

    async def test_submit_empty_answers_returns_a1(self, auth_client):
        """Empty answer list gives zero score → A1."""
        mock_rank = MagicMock()
        mock_rank.rank.value = "bronze"
        mock_rank.name = "Bronze I"
        with patch("app.routes.proficiency.calculate_rank", return_value=mock_rank):
            response = await auth_client.post(
                f"{BASE}/placement-test/submit",
                json={"answers": []},
            )
        assert response.status_code == 200
        assert response.json()["assessed_level"] == "A1"

    async def test_submit_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated submission is rejected."""
        response = await no_auth_client.post(
            f"{BASE}/placement-test/submit",
            json={"answers": []},
        )
        assert response.status_code in (401, 403)


# ===========================================================================
# POST /proficiency/exam-gated/submit
# ===========================================================================

class TestExamGatedProgression:

    async def test_exam_gated_submit_returns_200(self, auth_client_with_profile):
        """Valid exam-gated payload returns 200."""
        response = await auth_client_with_profile.post(
            f"{BASE}/exam-gated/submit",
            json={
                "exam_level": "A1",
                "passed": True,
                "score": 90,
                "passing_score": 70,
            },
        )
        assert response.status_code == 200

    async def test_exam_gated_promotes_one_tier_when_eligible(self, auth_client_with_profile):
        """Passing current-tier exam promotes to the next CEFR tier (max +1)."""
        response = await auth_client_with_profile.post(
            f"{BASE}/exam-gated/submit",
            json={
                "exam_level": "A1",
                "passed": True,
                "score": 85,
                "passing_score": 70,
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["previous_level"] == "A1"
        assert data["current_level"] == "A2"
        assert data["promoted"] is True
        assert data["promoted_to"] == "A2"

    async def test_exam_gated_does_not_promote_when_failed(self, auth_client_with_profile):
        """Failed exam (or below threshold) does not promote."""
        response = await auth_client_with_profile.post(
            f"{BASE}/exam-gated/submit",
            json={
                "exam_level": "A1",
                "passed": False,
                "score": 69,
                "passing_score": 70,
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["current_level"] == "A1"
        assert data["promoted"] is False
        assert data["promoted_to"] is None

    async def test_exam_gated_rejects_lower_tier_exam(self, auth_client_with_profile):
        """Exam tier below current level is ineligible for promotion."""
        mock_profile = _make_mock_profile()
        mock_profile.assessed_level = "B1"

        from app.main import app
        from app.core.database import get_db
        from app.core.dependencies import get_current_user

        mock_user = MagicMock()
        mock_user.id = TEST_USER_ID
        mock_user.level = "B1"
        mock_user.numeric_level = 3
        mock_user.total_xp = 600
        mock_user.rank = "silver"

        async def mock_get_db_b1():
            mock_result = MagicMock()
            mock_result.scalar.return_value = 0
            mock_result.scalar_one_or_none.return_value = mock_profile
            mock_result.scalars.return_value.all.return_value = []

            mock_session = MagicMock()

            async def fake_execute(query):
                return mock_result

            mock_session.execute = fake_execute
            mock_session.add = MagicMock()
            mock_session.commit = AsyncMock()
            mock_session.refresh = AsyncMock()
            yield mock_session

        async def mock_get_current_user_b1():
            return mock_user

        app.dependency_overrides[get_db] = mock_get_db_b1
        app.dependency_overrides[get_current_user] = mock_get_current_user_b1

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                f"{BASE}/exam-gated/submit",
                json={
                    "exam_level": "A2",
                    "passed": True,
                    "score": 95,
                    "passing_score": 70,
                },
            )

        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert data["previous_level"] == "B1"
        assert data["current_level"] == "B1"
        assert data["promoted"] is False
        assert data["eligible"] is False

    async def test_exam_gated_without_auth_returns_401_or_403(self, no_auth_client):
        """Unauthenticated exam-gated submission is rejected."""
        response = await no_auth_client.post(
            f"{BASE}/exam-gated/submit",
            json={
                "exam_level": "A1",
                "passed": True,
                "score": 88,
                "passing_score": 70,
            },
        )
        assert response.status_code in (401, 403)
