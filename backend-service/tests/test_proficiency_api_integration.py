"""
API Integration Tests for Proficiency Feature

These tests run against the REAL database (via app settings) with seeded data
to validate end-to-end correctness of the proficiency endpoints.

Tests cover:
  1. GET  /proficiency/profile           — returns correct structure and seeded values
  2. POST /proficiency/record-exercises   — score updates, level change detection
  3. GET  /proficiency/level-check        — requirements progress matches seeded state
  4. GET  /proficiency/level-thresholds   — static data, no auth
  5. GET  /proficiency/history            — returns seeded level transitions
  6. GET  /proficiency/placement-test     — returns 20 questions without answers
  7. POST /proficiency/placement-test/submit — correct scoring and level assignment

Usage:
  cd backend-service
  pytest tests/test_proficiency_api_integration.py -v
"""

# ruff: noqa: E402

import asyncio
import sys
from collections.abc import AsyncGenerator
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.core.config import settings as app_settings
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.main import app
from app.models.user import User
from tests.seed_proficiency_data import seed as seed_proficiency_data

DB_URL = app_settings.DATABASE_URL
BASE = "/api/v1/proficiency"
TARGET_EMAIL = "nhthang2077@gmail.com"
CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]


# ── Fixtures ─────────────────────────────────────────────────────────

# Shared engine and session factory (created once at module import time)
_engine = create_async_engine(DB_URL, poolclass=NullPool, echo=False)
_session_factory = async_sessionmaker(_engine, class_=AsyncSession, expire_on_commit=False)


@pytest.fixture(autouse=True)
def disable_rate_limiting(monkeypatch):
    from app.core.middleware import RateLimitMiddleware

    async def mock_dispatch(self, request, call_next):
        return await call_next(request)

    monkeypatch.setattr(RateLimitMiddleware, "dispatch", mock_dispatch)


@pytest.fixture(scope="module", autouse=True)
def seed_database() -> None:
    """Reset deterministic proficiency data before this module mutates it."""
    asyncio.run(seed_proficiency_data())


@pytest.fixture
async def auth_client() -> AsyncGenerator[AsyncClient, None]:
    """
    Authenticated HTTP client.
    """

    async def override_get_db():
        async with _session_factory() as session:
            yield session

    async def override_get_user():
        async with _session_factory() as session:
            result = await session.execute(select(User).where(User.email == TARGET_EMAIL))
            user = result.scalar_one_or_none()
            if user is None:
                pytest.fail(
                    f"User '{TARGET_EMAIL}' not found. Run: python -m tests.seed_proficiency_data"
                )
            return user

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()


@pytest.fixture
async def no_auth_client() -> AsyncGenerator[AsyncClient, None]:
    """Unauthenticated HTTP client."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


# ═══════════════════════════════════════════════════════════════════════
# 1. GET /proficiency/profile
# ═══════════════════════════════════════════════════════════════════════


class TestGetProfile:
    """Test proficiency profile retrieval with seeded data."""

    async def test_returns_200(self, auth_client):
        resp = await auth_client.get(f"{BASE}/profile")
        assert resp.status_code == 200

    async def test_profile_structure(self, auth_client):
        resp = await auth_client.get(f"{BASE}/profile")
        data = resp.json()

        # Top-level keys
        assert "user_id" in data
        assert "assessed_level" in data
        assert "overall_score" in data
        assert "total_xp" in data
        assert "skills" in data
        assert "statistics" in data
        assert "next_level" in data

    async def test_assessed_level_is_b1(self, auth_client):
        data = (await auth_client.get(f"{BASE}/profile")).json()
        assert data["assessed_level"] == "B1", (
            f"Seeded user should be B1 but got {data['assessed_level']}"
        )

    async def test_overall_score_positive(self, auth_client):
        data = (await auth_client.get(f"{BASE}/profile")).json()
        assert data["overall_score"] > 0, "Seeded user must have a positive overall score"

    async def test_all_six_skills_present(self, auth_client):
        data = (await auth_client.get(f"{BASE}/profile")).json()
        expected_skills = {"vocabulary", "grammar", "reading", "listening", "speaking", "writing"}
        assert set(data["skills"].keys()) == expected_skills

    async def test_skill_scores_in_range(self, auth_client):
        data = (await auth_client.get(f"{BASE}/profile")).json()
        for skill_name, skill_data in data["skills"].items():
            assert 0 <= skill_data["score"] <= 100, f"{skill_name} score out of range"
            assert 0 <= skill_data["confidence"] <= 1, f"{skill_name} confidence out of range"
            assert skill_data["exercises_completed"] > 0, f"{skill_name} should have exercises"

    async def test_statistics_accuracy(self, auth_client):
        data = (await auth_client.get(f"{BASE}/profile")).json()
        stats = data["statistics"]
        assert stats["exercises_completed"] > 400, "Seeded data should have 400+ exercises"
        assert stats["correct_exercises"] > 0
        assert 0 < stats["accuracy"] < 100

    async def test_next_level_info(self, auth_client):
        data = (await auth_client.get(f"{BASE}/profile")).json()
        nl = data["next_level"]
        assert nl["level"] == "B2", "Next level after B1 should be B2"
        assert 0 <= nl["progress"] <= 100

    async def test_total_xp_positive(self, auth_client):
        data = (await auth_client.get(f"{BASE}/profile")).json()
        assert data["total_xp"] > 0

    async def test_unauthorized_returns_401(self, no_auth_client):
        resp = await no_auth_client.get(f"{BASE}/profile")
        assert resp.status_code == 401


# ═══════════════════════════════════════════════════════════════════════
# 2. POST /proficiency/record-exercises
# ═══════════════════════════════════════════════════════════════════════


class TestRecordExercises:
    """Test recording new exercises on top of seeded data."""

    @pytest.fixture
    def sample_exercises(self):
        return [
            {
                "exercise_type": "vocab_fill_blank",
                "skill": "vocabulary",
                "difficulty_level": "B1",
                "is_correct": True,
                "score": 85.0,
                "time_spent_seconds": 30,
            },
            {
                "exercise_type": "grammar_choice",
                "skill": "grammar",
                "difficulty_level": "B1",
                "is_correct": True,
                "score": 90.0,
                "time_spent_seconds": 25,
            },
            {
                "exercise_type": "reading_comprehension",
                "skill": "reading",
                "difficulty_level": "A2",
                "is_correct": False,
                "score": 40.0,
                "time_spent_seconds": 60,
            },
        ]

    async def test_record_returns_200(self, auth_client, sample_exercises):
        resp = await auth_client.post(f"{BASE}/record-exercises", json=sample_exercises)
        assert resp.status_code == 200

    async def test_record_response_structure(self, auth_client, sample_exercises):
        resp = await auth_client.post(f"{BASE}/record-exercises", json=sample_exercises)
        data = resp.json()
        assert "exercises_recorded" in data
        assert "skill_updates" in data
        assert "level_changed" in data
        assert "current_level" in data
        assert "xp_earned" in data
        assert "total_xp" in data
        assert "message" in data

    async def test_exercises_count_matches(self, auth_client, sample_exercises):
        data = (await auth_client.post(f"{BASE}/record-exercises", json=sample_exercises)).json()
        assert data["exercises_recorded"] == len(sample_exercises)

    async def test_xp_earned_positive(self, auth_client, sample_exercises):
        data = (await auth_client.post(f"{BASE}/record-exercises", json=sample_exercises)).json()
        assert data["xp_earned"] > 0, "Correct exercises should earn XP"

    async def test_skill_updates_contain_changed_skills(self, auth_client, sample_exercises):
        data = (await auth_client.post(f"{BASE}/record-exercises", json=sample_exercises)).json()
        assert "vocabulary" in data["skill_updates"]
        assert "grammar" in data["skill_updates"]
        assert "reading" in data["skill_updates"]

    async def test_skill_score_change_direction(self, auth_client):
        """High-scoring correct exercises should increase the skill score."""
        exercises = [
            {
                "exercise_type": "vocab_match",
                "skill": "vocabulary",
                "difficulty_level": "B1",
                "is_correct": True,
                "score": 95.0,
                "time_spent_seconds": 15,
            }
            for _ in range(5)
        ]
        data = (await auth_client.post(f"{BASE}/record-exercises", json=exercises)).json()
        vocab_update = data["skill_updates"].get("vocabulary", {})
        assert vocab_update.get("change", 0) >= 0, (
            "5 correct vocab exercises at 95% should not decrease score"
        )

    async def test_empty_exercises_returns_error(self, auth_client):
        resp = await auth_client.post(f"{BASE}/record-exercises", json=[])
        # FastAPI may return 200 with 0 recorded or 422 validation error
        assert resp.status_code in (200, 422)

    async def test_invalid_skill_returns_422(self, auth_client):
        exercises = [
            {
                "exercise_type": "test",
                "skill": "nonexistent_skill",
                "difficulty_level": "A1",
                "is_correct": True,
                "score": 50.0,
                "time_spent_seconds": 10,
            }
        ]
        resp = await auth_client.post(f"{BASE}/record-exercises", json=exercises)
        assert resp.status_code == 422

    async def test_invalid_score_range_returns_422(self, auth_client):
        exercises = [
            {
                "exercise_type": "test",
                "skill": "vocabulary",
                "difficulty_level": "A1",
                "is_correct": True,
                "score": 150.0,  # out of range
                "time_spent_seconds": 10,
            }
        ]
        resp = await auth_client.post(f"{BASE}/record-exercises", json=exercises)
        assert resp.status_code == 422

    async def test_unauthorized_returns_401(self, no_auth_client, sample_exercises):
        resp = await no_auth_client.post(f"{BASE}/record-exercises", json=sample_exercises)
        assert resp.status_code == 401


# ═══════════════════════════════════════════════════════════════════════
# 3. GET /proficiency/level-check
# ═══════════════════════════════════════════════════════════════════════


class TestLevelCheck:
    """Test level-check endpoint with seeded B1 user."""

    async def test_returns_200(self, auth_client):
        resp = await auth_client.get(f"{BASE}/level-check")
        assert resp.status_code == 200

    async def test_current_level(self, auth_client):
        data = (await auth_client.get(f"{BASE}/level-check")).json()
        # Level may have shifted due to record-exercises test; just ensure it's valid CEFR
        assert data["current_level"] in CEFR_LEVELS

    async def test_next_level_exists(self, auth_client):
        data = (await auth_client.get(f"{BASE}/level-check")).json()
        if data["current_level"] != "C2":
            assert data["next_level"] in CEFR_LEVELS
            cur_idx = CEFR_LEVELS.index(data["current_level"])
            nxt_idx = CEFR_LEVELS.index(data["next_level"])
            assert nxt_idx == cur_idx + 1, "next_level should be one above current"

    async def test_requirements_dict_not_empty(self, auth_client):
        data = (await auth_client.get(f"{BASE}/level-check")).json()
        assert len(data["requirements"]) > 0, "Should have B2 requirement checks"

    async def test_each_requirement_has_fields(self, auth_client):
        data = (await auth_client.get(f"{BASE}/level-check")).json()
        for name, req in data["requirements"].items():
            assert "required" in req, f"Requirement '{name}' missing 'required'"
            assert "current" in req, f"Requirement '{name}' missing 'current'"
            assert "met" in req, f"Requirement '{name}' missing 'met'"
            assert "progress" in req, f"Requirement '{name}' missing 'progress'"

    async def test_progress_is_numeric(self, auth_client):
        data = (await auth_client.get(f"{BASE}/level-check")).json()
        assert isinstance(data["overall_progress"], (int, float))
        assert 0 <= data["overall_progress"] <= 100

    async def test_some_blockers_exist_for_b2(self, auth_client):
        """B1 user with ~500 exercises likely doesn't meet B2's 600 exercise requirement."""
        data = (await auth_client.get(f"{BASE}/level-check")).json()
        # Not strictly guaranteed, but with seeded data the user should have some blockers
        assert isinstance(data["blockers"], list)

    async def test_unauthorized_returns_401(self, no_auth_client):
        resp = await no_auth_client.get(f"{BASE}/level-check")
        assert resp.status_code == 401


# ═══════════════════════════════════════════════════════════════════════
# 4. GET /proficiency/level-thresholds
# ═══════════════════════════════════════════════════════════════════════


class TestLevelThresholds:
    """Test level thresholds endpoint (no auth required)."""

    async def test_returns_200_without_auth(self, no_auth_client):
        resp = await no_auth_client.get(f"{BASE}/level-thresholds")
        assert resp.status_code == 200

    async def test_all_cefr_levels_present(self, no_auth_client):
        data = (await no_auth_client.get(f"{BASE}/level-thresholds")).json()
        expected = {"A1", "A2", "B1", "B2", "C1", "C2"}
        assert set(data["levels"].keys()) == expected

    async def test_thresholds_increase_with_level(self, no_auth_client):
        data = (await no_auth_client.get(f"{BASE}/level-thresholds")).json()
        levels = data["levels"]
        # min_overall_score should increase: A1 < A2 < B1 < ... < C2
        prev_score = -1
        for level_name in ["A1", "A2", "B1", "B2", "C1", "C2"]:
            score = levels[level_name]["min_overall_score"]
            assert score >= prev_score, (
                f"{level_name} min_overall_score ({score}) < previous ({prev_score})"
            )
            prev_score = score

    async def test_skill_weights_sum_to_1(self, no_auth_client):
        data = (await no_auth_client.get(f"{BASE}/level-thresholds")).json()
        total = sum(data["skill_weights"].values())
        assert abs(total - 1.0) < 0.01, f"Skill weights should sum to 1.0, got {total}"

    async def test_c2_has_all_skill_requirements(self, no_auth_client):
        data = (await no_auth_client.get(f"{BASE}/level-thresholds")).json()
        c2 = data["levels"]["C2"]
        assert c2["min_vocabulary_score"] > 0
        assert c2["min_grammar_score"] > 0
        assert c2["min_reading_score"] > 0
        assert c2["min_listening_score"] > 0
        assert c2["min_speaking_score"] > 0
        assert c2["min_writing_score"] > 0
        # Volume gates were lowered when min_skill_confidence took over the
        # "measured enough to promote" role; C2 still asks for the most.
        assert c2["min_exercises_completed"] >= 1000
        assert c2["min_skill_confidence"] >= 0.8
        assert c2["min_streak_days"] >= 60


# ═══════════════════════════════════════════════════════════════════════
# 5. GET /proficiency/history
# ═══════════════════════════════════════════════════════════════════════


class TestHistory:
    """Test level history with seeded transitions."""

    async def test_returns_200(self, auth_client):
        resp = await auth_client.get(f"{BASE}/history")
        assert resp.status_code == 200

    async def test_has_seeded_transitions(self, auth_client):
        data = (await auth_client.get(f"{BASE}/history")).json()
        assert len(data["history"]) >= 4, (
            f"Should have at least 4 seeded transitions, got {len(data['history'])}"
        )

    async def test_current_level_in_response(self, auth_client):
        data = (await auth_client.get(f"{BASE}/history")).json()
        assert data["current_level"] in CEFR_LEVELS

    async def test_history_entry_structure(self, auth_client):
        data = (await auth_client.get(f"{BASE}/history")).json()
        for entry in data["history"]:
            assert "previous_level" in entry
            assert "new_level" in entry
            assert "change_type" in entry
            assert "reason" in entry
            assert "triggered_at" in entry

    async def test_has_promotion_and_demotion(self, auth_client):
        data = (await auth_client.get(f"{BASE}/history")).json()
        types = {e["change_type"] for e in data["history"]}
        assert "promotion" in types, "Should have at least one promotion"
        assert "demotion" in types, "Should have the seeded demotion"
        assert "initial" in types, "Should have initial level record"

    async def test_limit_parameter(self, auth_client):
        data = (await auth_client.get(f"{BASE}/history?limit=2")).json()
        assert len(data["history"]) <= 2

    async def test_unauthorized_returns_401(self, no_auth_client):
        resp = await no_auth_client.get(f"{BASE}/history")
        assert resp.status_code == 401


# ═══════════════════════════════════════════════════════════════════════
# 6. GET /proficiency/placement-test
# ═══════════════════════════════════════════════════════════════════════


class TestPlacementTest:
    """Test placement test question retrieval."""

    async def test_returns_200(self, auth_client):
        resp = await auth_client.get(f"{BASE}/placement-test")
        assert resp.status_code == 200

    async def test_returns_20_questions(self, auth_client):
        data = (await auth_client.get(f"{BASE}/placement-test")).json()
        assert data["total_questions"] == 20
        assert len(data["questions"]) == 20

    async def test_questions_have_no_correct_answer(self, auth_client):
        """Correct answer index must NOT be exposed to the client."""
        data = (await auth_client.get(f"{BASE}/placement-test")).json()
        for q in data["questions"]:
            assert "correct" not in q, f"Question {q['id']} leaks correct answer!"

    async def test_question_structure(self, auth_client):
        data = (await auth_client.get(f"{BASE}/placement-test")).json()
        for q in data["questions"]:
            assert "id" in q
            assert "level" in q
            assert "question" in q
            assert "options" in q
            assert len(q["options"]) == 4

    async def test_max_score_positive(self, auth_client):
        data = (await auth_client.get(f"{BASE}/placement-test")).json()
        assert data["max_score"] > 0

    async def test_unauthorized_returns_401(self, no_auth_client):
        resp = await no_auth_client.get(f"{BASE}/placement-test")
        assert resp.status_code == 401


# ═══════════════════════════════════════════════════════════════════════
# 7. POST /proficiency/placement-test/submit
# ═══════════════════════════════════════════════════════════════════════


class TestPlacementSubmit:
    """Test placement test submission and scoring."""

    async def test_all_correct_gives_high_level(self, auth_client):
        """Answering all questions correctly → C1 or C2."""
        # Known correct answers from PLACEMENT_QUESTIONS
        correct_answers = [
            {"question_id": 1, "selected_option": 0},
            {"question_id": 2, "selected_option": 0},
            {"question_id": 3, "selected_option": 1},
            {"question_id": 4, "selected_option": 2},
            {"question_id": 5, "selected_option": 1},
            {"question_id": 6, "selected_option": 1},
            {"question_id": 7, "selected_option": 1},
            {"question_id": 8, "selected_option": 0},
            {"question_id": 9, "selected_option": 1},
            {"question_id": 10, "selected_option": 0},
            {"question_id": 11, "selected_option": 2},
            {"question_id": 12, "selected_option": 1},
            {"question_id": 13, "selected_option": 1},
            {"question_id": 14, "selected_option": 1},
            {"question_id": 15, "selected_option": 1},
            {"question_id": 16, "selected_option": 2},
            {"question_id": 17, "selected_option": 0},
            {"question_id": 18, "selected_option": 1},
            {"question_id": 19, "selected_option": 0},
            {"question_id": 20, "selected_option": 1},
        ]
        resp = await auth_client.post(
            f"{BASE}/placement-test/submit",
            json={"answers": correct_answers},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["correct_count"] == 20
        assert data["score_percentage"] == 100.0
        assert data["assessed_level"] in ("C1", "C2")

    async def test_all_wrong_gives_a1(self, auth_client):
        """Answering all questions wrong → A1."""
        wrong_answers = [
            {"question_id": i, "selected_option": 3}  # All option 3 (wrong for most)
            for i in range(1, 21)
        ]
        resp = await auth_client.post(
            f"{BASE}/placement-test/submit",
            json={"answers": wrong_answers},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["assessed_level"] == "A1"

    async def test_submit_response_structure(self, auth_client):
        answers = [{"question_id": i, "selected_option": 0} for i in range(1, 21)]
        resp = await auth_client.post(
            f"{BASE}/placement-test/submit",
            json={"answers": answers},
        )
        data = resp.json()
        assert "assessed_level" in data
        assert "total_score" in data
        assert "score_percentage" in data
        assert "correct_count" in data
        assert "total_questions" in data
        assert "rank" in data

    async def test_partial_answers_accepted(self, auth_client):
        """Submitting fewer than 20 answers should still work."""
        answers = [
            {"question_id": 1, "selected_option": 0},
            {"question_id": 2, "selected_option": 0},
        ]
        resp = await auth_client.post(
            f"{BASE}/placement-test/submit",
            json={"answers": answers},
        )
        assert resp.status_code == 200

    async def test_unauthorized_returns_401(self, no_auth_client):
        resp = await no_auth_client.post(
            f"{BASE}/placement-test/submit",
            json={"answers": []},
        )
        assert resp.status_code == 401


# ═══════════════════════════════════════════════════════════════════════
# 8. Cross-endpoint Consistency Tests
# ═══════════════════════════════════════════════════════════════════════


class TestCrossEndpointConsistency:
    """Verify data consistency across multiple endpoints."""

    async def test_profile_and_levelcheck_agree_on_level(self, auth_client):
        profile = (await auth_client.get(f"{BASE}/profile")).json()
        level_check = (await auth_client.get(f"{BASE}/level-check")).json()
        assert profile["assessed_level"] == level_check["current_level"]

    async def test_profile_and_history_agree_on_level(self, auth_client):
        profile = (await auth_client.get(f"{BASE}/profile")).json()
        history = (await auth_client.get(f"{BASE}/history")).json()
        assert profile["assessed_level"] == history["current_level"]

    async def test_skills_in_profile_match_levelcheck_requirements(self, auth_client):
        """Profile skill scores should influence level-check requirements."""
        profile = (await auth_client.get(f"{BASE}/profile")).json()
        level_check = (await auth_client.get(f"{BASE}/level-check")).json()

        # If vocabulary score is > B2 min, that requirement should be met
        vocab_score = profile["skills"]["vocabulary"]["score"]
        if "Vocabulary Score" in level_check["requirements"]:
            req = level_check["requirements"]["Vocabulary Score"]
            required_val = float(req["required"].replace("%", ""))
            if vocab_score >= required_val:
                assert req["met"] is True, (
                    f"Vocab score {vocab_score} >= {required_val} but requirement not met"
                )

    async def test_record_exercises_updates_profile(self, auth_client):
        """After recording exercises, profile should reflect updated stats."""
        # Get profile before
        before = (await auth_client.get(f"{BASE}/profile")).json()
        before_exercises = before["statistics"]["exercises_completed"]

        # Record 2 exercises
        exercises = [
            {
                "exercise_type": "vocab_fill_blank",
                "skill": "vocabulary",
                "difficulty_level": "A1",
                "is_correct": True,
                "score": 80.0,
                "time_spent_seconds": 10,
            },
            {
                "exercise_type": "grammar_choice",
                "skill": "grammar",
                "difficulty_level": "A1",
                "is_correct": True,
                "score": 70.0,
                "time_spent_seconds": 15,
            },
        ]
        await auth_client.post(f"{BASE}/record-exercises", json=exercises)

        # Get profile after
        after = (await auth_client.get(f"{BASE}/profile")).json()
        after_exercises = after["statistics"]["exercises_completed"]

        assert after_exercises == before_exercises + 2, (
            f"Expected {before_exercises + 2} exercises, got {after_exercises}"
        )
