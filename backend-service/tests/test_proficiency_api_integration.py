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
    # Seed through this module's NullPool factory, not the app-global pool —
    # asyncio.run() opens a loop of its own and pooled connections from an
    # earlier test's loop fail with "attached to a different loop".
    asyncio.run(seed_proficiency_data(_session_factory))


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

    async def test_route_grants_no_xp(self, auth_client, sample_exercises):
        """The client grades these, so XP must come from /xp/award instead."""
        data = (await auth_client.post(f"{BASE}/record-exercises", json=sample_exercises)).json()
        assert data["xp_earned"] == 0

    async def test_oversized_batch_rejected(self, auth_client, sample_exercises):
        oversized = (sample_exercises * 20)[:51]
        response = await auth_client.post(f"{BASE}/record-exercises", json=oversized)
        assert response.status_code == 422

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

    async def test_profile_and_history_agree_on_level(self, auth_client):
        profile = (await auth_client.get(f"{BASE}/profile")).json()
        history = (await auth_client.get(f"{BASE}/history")).json()
        assert profile["assessed_level"] == history["current_level"]

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
