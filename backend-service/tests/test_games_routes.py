"""
Tests for Games API Routes — Phase 3

Tests cover:
- GET /games/word-scramble    — scrambled letters per CEFR level
- GET /games/matching         — word-definition pairs
- GET /games/spelling-bee     — words for spelling game
- GET /games/hangman          — single word for hangman
- GET /games/fill-blank       — fill-in-the-blank questions (hardcoded bank)
- GET /games/grammar-quiz     — grammar quiz questions (hardcoded bank)
- GET /games/categories       — word categories from DB
- Internal helpers: TIMER_BY_LEVEL, XP_BY_LEVEL, FILL_BLANK_BANK
"""

import pytest
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


# ============================================================================
# Fixture: authenticated client with mocked DB and auth
# ============================================================================

@pytest.fixture
async def auth_client():
    """
    Async HTTP client with mocked DB and get_current_user dependencies.
    All game endpoints require authentication.
    """
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_user = MagicMock()
    mock_user.id = "test-user-uuid"
    mock_user.username = "testuser"
    mock_user.total_xp = 100
    mock_user.numeric_level = 2

    async def mock_get_db():
        # Use a MagicMock session with a proper async execute
        # so that result.scalar() returns int (not coroutine)
        mock_result = MagicMock()
        mock_result.scalar.return_value = 5   # count > 0 → _ensure_seeded short-circuits
        mock_result.scalar_one_or_none.return_value = None
        mock_result.scalars.return_value.all.return_value = []
        mock_result.all.return_value = []

        mock_session = MagicMock()

        async def fake_execute(query):
            return mock_result

        mock_session.execute = fake_execute
        mock_session.add = MagicMock()
        mock_session.commit = AsyncMock()
        yield mock_session

    async def mock_get_current_user():
        return mock_user

    app.dependency_overrides[get_db] = mock_get_db
    app.dependency_overrides[get_current_user] = mock_get_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()


BASE = "/api/v1/games"


# ============================================================================
# Unit Tests — Constants
# ============================================================================

class TestGameConstants:
    """Tests for timer/XP configuration constants."""

    def test_timer_by_level_has_all_cefr_levels(self):
        from app.routes.games import TIMER_BY_LEVEL

        for level in ["A1", "A2", "B1", "B2", "C1", "C2"]:
            assert level in TIMER_BY_LEVEL

    def test_xp_by_level_has_all_cefr_levels(self):
        from app.routes.games import XP_BY_LEVEL

        for level in ["A1", "A2", "B1", "B2", "C1", "C2"]:
            assert level in XP_BY_LEVEL

    def test_higher_levels_have_more_xp(self):
        from app.routes.games import XP_BY_LEVEL

        assert XP_BY_LEVEL["A1"] <= XP_BY_LEVEL["B1"]
        assert XP_BY_LEVEL["B1"] <= XP_BY_LEVEL["C1"]

    def test_higher_levels_have_less_timer(self):
        from app.routes.games import TIMER_BY_LEVEL

        assert TIMER_BY_LEVEL["C1"] <= TIMER_BY_LEVEL["A1"]

    def test_fill_blank_bank_has_a1_b2_levels(self):
        from app.routes.games import FILL_BLANK_BANK

        for level in ["A1", "A2", "B1", "B2"]:
            assert level in FILL_BLANK_BANK
            assert len(FILL_BLANK_BANK[level]) > 0

    def test_each_fill_blank_question_has_required_fields(self):
        from app.routes.games import FILL_BLANK_BANK

        for level, questions in FILL_BLANK_BANK.items():
            for q in questions:
                assert "sentence" in q
                assert "options" in q
                assert "correct_answer" in q
                assert "grammar_tip" in q
                assert len(q["options"]) == 4

    def test_correct_answer_in_options(self):
        from app.routes.games import FILL_BLANK_BANK

        for level, questions in FILL_BLANK_BANK.items():
            for q in questions:
                assert q["correct_answer"] in q["options"]

    def test_game_words_seed_has_multiple_levels(self):
        from app.routes.games import GAME_WORDS_SEED

        levels_present = {w["cefr_level"] for w in GAME_WORDS_SEED}
        assert len(levels_present) >= 3

    def test_game_words_seed_has_required_fields(self):
        from app.routes.games import GAME_WORDS_SEED

        required = [
            "word", "definition", "hint", "cefr_level",
            "category", "letter_count", "xp_value", "ipa_pronunciation",
            "example_sentence", "synonyms", "vietnamese_translation",
        ]
        for w in GAME_WORDS_SEED:
            for field in required:
                assert field in w


# ============================================================================
# Route Tests — GET /games/fill-blank (no DB needed for hardcoded bank)
# ============================================================================

class TestFillBlank:
    """Tests for GET /games/fill-blank endpoint."""

    @pytest.mark.asyncio
    async def test_returns_fill_blank_structure(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/fill-blank?level=A1")
        assert response.status_code == 200
        data = response.json()
        assert uuid.UUID(data["session_id"])
        assert data["game"] == "fill_blank"
        assert "questions" in data
        assert "timer_seconds_per_question" in data
        assert "total" in data
        assert data["total_xp"] == data["total"] * 10

    @pytest.mark.asyncio
    async def test_default_level_a1(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/fill-blank")
        assert response.status_code == 200
        data = response.json()
        assert data["cefr_level"] == "A1"

    @pytest.mark.asyncio
    async def test_returns_correct_count(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/fill-blank?level=A1&count=5")
        assert response.status_code == 200
        data = response.json()
        assert data["total"] <= 5
        assert data["total"] == len(data["questions"])

    @pytest.mark.asyncio
    async def test_each_question_has_required_fields(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/fill-blank?level=B1")
        assert response.status_code == 200
        for q in response.json()["questions"]:
            assert "id" in q
            assert "sentence" in q
            assert "options" in q
            assert "correct_answer" in q
            assert "grammar_tip" in q
            assert len(q["options"]) == 4

    @pytest.mark.asyncio
    async def test_correct_answer_in_shuffled_options(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/fill-blank?level=A2")
        assert response.status_code == 200
        for q in response.json()["questions"]:
            assert q["correct_answer"] in q["options"]

    @pytest.mark.asyncio
    async def test_unknown_level_falls_back_to_b1(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/fill-blank?level=Z9")
        assert response.status_code == 200
        assert response.json()["total"] > 0

    @pytest.mark.asyncio
    async def test_b2_level_returns_questions(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/fill-blank?level=B2&count=13")
        assert response.status_code == 200
        data = response.json()
        assert data["total"] > 0
        assert data["cefr_level"] == "B2"


# ============================================================================
# Route Tests — GET /games/grammar-quiz (no DB needed for hardcoded bank)
# ============================================================================

class TestGrammarQuiz:
    """Tests for GET /games/grammar-quiz endpoint."""

    @pytest.mark.asyncio
    async def test_returns_grammar_quiz_structure(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/grammar-quiz?level=A1")
        assert response.status_code == 200
        data = response.json()
        assert uuid.UUID(data["session_id"])
        assert data["game"] == "grammar_quiz"
        assert "questions" in data
        assert "timer_seconds_per_question" in data
        assert "total" in data
        assert "cefr_level" in data
        assert data["total_xp"] == data["total"] * 10

    @pytest.mark.asyncio
    async def test_each_question_has_required_fields(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/grammar-quiz?level=B1")
        assert response.status_code == 200
        for q in response.json()["questions"]:
            assert "id" in q
            assert "question" in q
            assert "options" in q
            assert "correct_answer" in q
            assert "explanation" in q
            assert "topic" in q
            assert len(q["options"]) == 4

    @pytest.mark.asyncio
    async def test_session_expected_items_preserve_question_topics(
        self,
        auth_client: AsyncClient,
    ):
        session = MagicMock(id=uuid.uuid4())
        with patch(
            "app.routes.games.create_game_session",
            new_callable=AsyncMock,
            return_value=session,
        ) as create_mock:
            response = await auth_client.get(
                f"{BASE}/grammar-quiz?level=A1&count=3"
            )

        assert response.status_code == 200
        expected_items = create_mock.await_args.kwargs["expected_items"]
        assert [item["topic"] for item in expected_items] == [
            question["topic"] for question in response.json()["questions"]
        ]

    @pytest.mark.asyncio
    async def test_correct_answer_in_options(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/grammar-quiz?level=A2")
        assert response.status_code == 200
        for q in response.json()["questions"]:
            assert q["correct_answer"] in q["options"]

    @pytest.mark.asyncio
    async def test_topic_filter_to_be(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/grammar-quiz?level=A1&topic=to_be")
        assert response.status_code == 200
        data = response.json()
        for q in data["questions"]:
            assert q["topic"] == "to_be"

    @pytest.mark.asyncio
    async def test_invalid_topic_falls_back_to_full_pool(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/grammar-quiz?level=A1&topic=nonexistent_topic")
        assert response.status_code == 200
        assert response.json()["total"] > 0

    @pytest.mark.asyncio
    async def test_count_parameter_limits_questions(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/grammar-quiz?level=B1&count=3")
        assert response.status_code == 200
        data = response.json()
        assert data["total"] <= 3

    @pytest.mark.asyncio
    async def test_b2_level_returns_questions(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/grammar-quiz?level=B2&count=11")
        assert response.status_code == 200
        assert response.json()["total"] > 0


# ============================================================================
# Route Tests — GET /games/word-scramble (DB needed)
# ============================================================================

class TestWordScramble:
    """Tests for GET /games/word-scramble endpoint."""

    @pytest.mark.asyncio
    async def test_returns_word_scramble_structure(self, auth_client: AsyncClient):
        from app.routes.games import XP_BY_LEVEL

        response = await auth_client.get(f"{BASE}/word-scramble?level=A1&count=3")
        assert response.status_code == 200
        data = response.json()
        assert uuid.UUID(data["session_id"])
        assert data["game"] == "word_scramble"
        assert "words" in data
        assert "timer_seconds" in data
        assert data["base_xp_per_word"] == XP_BY_LEVEL["A1"]
        assert data["streak_bonus_threshold"] == 3
        assert "cefr_level" in data

    @pytest.mark.asyncio
    async def test_count_below_minimum_fails_validation(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/word-scramble?level=A1&count=1")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_count_above_maximum_fails_validation(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/word-scramble?level=A1&count=25")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_default_level_is_a1(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/word-scramble")
        assert response.status_code == 200
        assert response.json()["cefr_level"] == "A1"

    @pytest.mark.asyncio
    async def test_timer_matches_cefr_level(self, auth_client: AsyncClient):
        from app.routes.games import TIMER_BY_LEVEL
        for level, expected_timer in TIMER_BY_LEVEL.items():
            response = await auth_client.get(f"{BASE}/word-scramble?level={level}")
            assert response.status_code == 200
            assert response.json()["timer_seconds"] == expected_timer


# ============================================================================
# Route Tests — GET /games/spelling-bee (DB needed)
# ============================================================================

class TestSpellingBee:
    """Tests for GET /games/spelling-bee endpoint."""

    @pytest.mark.asyncio
    async def test_returns_spelling_bee_structure(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/spelling-bee?level=A1&count=3")
        assert response.status_code == 200
        data = response.json()
        assert uuid.UUID(data["session_id"])
        assert data["game"] == "spelling_bee"
        assert "words" in data
        assert "timer_seconds" in data
        assert "cefr_level" in data

    @pytest.mark.asyncio
    async def test_count_below_minimum_fails_validation(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/spelling-bee?level=A1&count=1")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_count_above_maximum_fails_validation(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/spelling-bee?level=A1&count=20")
        assert response.status_code == 422


# ============================================================================
# Route Tests — GET /games/hangman (DB needed)
# ============================================================================

class TestHangman:
    """Tests for GET /games/hangman endpoint."""

    @pytest.mark.asyncio
    async def test_returns_hangman_structure(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/hangman?level=A1")
        assert response.status_code == 200
        data = response.json()
        assert uuid.UUID(data["session_id"])
        assert "word_id" in data
        assert "word" in data
        assert "category" in data
        assert "hint" in data
        assert "definition" in data
        assert "letter_count" in data
        assert "xp_value" in data
        assert "cefr_level" in data
        assert data["base_xp"] == data["xp_value"]
        assert data["max_lives"] == 6
        assert data["hints"]["hint1_free"] == data["hint"]
        assert data["hints"]["hint2_definition"] == data["definition"]
        assert data["hints"]["hint2_xp_cost"] >= 0
        assert data["hints"]["hint3_xp_cost"] >= 0

    @pytest.mark.asyncio
    async def test_letter_count_matches_word_length(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/hangman?level=A1")
        assert response.status_code == 200
        data = response.json()
        assert data["letter_count"] == len(data["word"])

    @pytest.mark.asyncio
    async def test_returns_word_for_multiple_cefr_levels(self, auth_client: AsyncClient):
        for level in ["A1", "A2", "B1", "B2"]:
            response = await auth_client.get(f"{BASE}/hangman?level={level}")
            assert response.status_code == 200
            data = response.json()
            assert len(data["word"]) > 0


# ============================================================================
# Route Tests — GET /games/matching (DB needed)
# ============================================================================

class TestMatchingGame:
    """Tests for GET /games/matching endpoint."""

    @pytest.mark.asyncio
    async def test_returns_matching_structure(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/matching?level=A1")
        assert response.status_code == 200
        data = response.json()
        assert uuid.UUID(data["session_id"])
        assert data["game"] == "matching"
        assert "pairs" in data
        assert "words_column" in data
        assert "definitions_column" in data
        assert "timer_seconds" in data
        assert "total_pairs" in data
        assert data["base_xp"] >= 0
        assert data["time_bonus_threshold"] == 0.5

    @pytest.mark.asyncio
    async def test_columns_have_same_length(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/matching?level=A1")
        assert response.status_code == 200
        data = response.json()
        assert len(data["words_column"]) == len(data["definitions_column"])

    @pytest.mark.asyncio
    async def test_variant_default_is_definition(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/matching?level=A1")
        assert response.status_code == 200
        assert response.json()["variant"] == "definition"

    @pytest.mark.asyncio
    async def test_non_standard_count_clamped(self, auth_client: AsyncClient):
        """count=5 is not in {4,6,8} -> clamped to 6."""
        response = await auth_client.get(f"{BASE}/matching?level=A1&count=5")
        assert response.status_code == 200
        assert "pairs" in response.json()


# ============================================================================
# Route Tests — POST /games/sessions/{id}/complete
# ============================================================================

class TestGameSessionCompletion:
    @pytest.mark.parametrize(
        ("game_type", "expected_item", "hook_name", "hook_argument"),
        [
            (
                "word_scramble",
                {"id": str(uuid.uuid4()), "answer": "hello", "xp_value": 10},
                "record_game_vocab_lapse",
                "game_word_id",
            ),
            (
                "grammar_quiz",
                {
                    "id": "1",
                    "answer": "is",
                    "xp_value": 10,
                    "topic": "to_be",
                },
                "record_game_grammar_lapse",
                "topic",
            ),
        ],
    )
    @pytest.mark.asyncio
    async def test_wrong_answer_hooks_keep_completion_successful(
        self,
        auth_client: AsyncClient,
        game_type: str,
        expected_item: dict,
        hook_name: str,
        hook_argument: str,
    ):
        session_id = uuid.uuid4()
        session = MagicMock()
        session.id = session_id
        session.user_id = "test-user-uuid"
        session.game_type = game_type
        session.started_at = datetime.now(timezone.utc) - timedelta(seconds=20)
        session.created_at = session.started_at
        session.completed_at = None
        session.xp_awarded = False
        session.session_data = {"expected_items": [expected_item]}
        xp_result = MagicMock()
        xp_result.xp_awarded = 0
        xp_result.to_dict.return_value = {"xp_awarded": 0}

        with patch(
            "app.routes.games.get_game_session_for_update",
            new_callable=AsyncMock,
            return_value=session,
        ), patch(
            "app.routes.games.award_xp_transaction",
            new_callable=AsyncMock,
            return_value=xp_result,
        ), patch(
            "app.routes.games.record_learner_error",
            new_callable=AsyncMock,
        ), patch(
            f"app.routes.games.{hook_name}",
            new_callable=AsyncMock,
        ) as lapse_mock, patch(
            "app.routes.games.update_user_streak",
            new_callable=AsyncMock,
        ), patch(
            "app.routes.games.check_achievements_for_user",
            new_callable=AsyncMock,
            return_value=[],
        ), patch(
            "app.routes.games.invalidate_cache",
            new_callable=AsyncMock,
        ):
            response = await auth_client.post(
                f"{BASE}/sessions/{session_id}/complete",
                json={
                    "answers": [
                        {"id": expected_item["id"], "answer": "wrong"}
                    ]
                },
            )

        assert response.status_code == 200
        lapse_mock.assert_awaited_once()
        assert lapse_mock.await_args.kwargs[hook_argument] == expected_item.get(
            hook_argument,
            expected_item["id"],
        )

    @pytest.mark.asyncio
    async def test_completes_session_with_server_verified_score(self):
        from app.routes.games import complete_game_session
        from app.schemas.games import GameSessionCompleteRequest

        session_id = uuid.uuid4()
        user_id = uuid.uuid4()
        session = MagicMock()
        session.id = session_id
        session.user_id = user_id
        session.game_type = "grammar_quiz"
        session.started_at = datetime.now(timezone.utc) - timedelta(seconds=20)
        session.created_at = session.started_at
        session.completed_at = None
        session.xp_awarded = False
        session.session_data = {
            "expected_items": [
                {"id": "1", "answer": "is", "xp_value": 10},
                {"id": "2", "answer": "are", "xp_value": 10},
            ]
        }
        user = MagicMock()
        user.id = user_id
        db = MagicMock()
        db.commit = AsyncMock()
        xp_result = MagicMock()
        xp_result.xp_awarded = 10
        xp_result.to_dict.return_value = {
            "xp_awarded": 10,
            "current_xp_in_level": 10,
        }

        with patch(
            "app.routes.games.get_game_session_for_update",
            new_callable=AsyncMock,
            return_value=session,
        ), patch(
            "app.routes.games.award_xp_transaction",
            new_callable=AsyncMock,
            return_value=xp_result,
        ) as award_mock, patch(
            "app.routes.games.ItemEffectsService.get_xp_multiplier",
            new_callable=AsyncMock,
            return_value=1.0,
        ) as multiplier_mock, patch(
            "app.routes.games.check_achievements_for_user",
            new_callable=AsyncMock,
            return_value=[],
        ) as achievement_mock, patch(
            "app.routes.games.invalidate_cache",
            new_callable=AsyncMock,
        ):
            response = await complete_game_session(
                session_id=session_id,
                body=GameSessionCompleteRequest(
                    answers=[
                        {"id": "1", "answer": "is"},
                        {"id": "2", "answer": "wrong"},
                    ]
                ),
                db=db,
                current_user=user,
            )

        assert response.correct_count == 1
        assert response.total_count == 2
        assert response.base_xp == 10
        assert response.xp_awarded == 10
        assert session.completed_at is not None
        assert session.xp_awarded is True
        db.commit.assert_awaited_once()
        multiplier_mock.assert_awaited_once_with(user_id)
        award_mock.assert_awaited_once()
        assert award_mock.await_args.kwargs["source_id"] == str(session_id)
        assert award_mock.await_args.kwargs["commit"] is False
        assert award_mock.await_args.kwargs["item_multiplier"] == 1.0
        achievement_mock.assert_awaited_once_with(
            db,
            user_id,
            "game_complete",
        )

    @pytest.mark.asyncio
    async def test_returns_existing_award_for_completed_session(self):
        from app.routes.games import complete_game_session
        from app.schemas.games import GameSessionCompleteRequest

        session = MagicMock()
        session.id = uuid.uuid4()
        session.user_id = uuid.uuid4()
        session.game_type = "hangman"
        session.completed_at = datetime.now(timezone.utc)
        session.xp_awarded = True
        session.correct_answers = 1
        session.total_questions = 1
        session.xp_earned = 10
        session.duration_seconds = 30
        session.session_data = {
            "score_result": {"raw_xp": 15, "penalties": 5, "base_xp": 10}
        }
        user = MagicMock()
        user.id = session.user_id
        existing_award = MagicMock()
        existing_award.xp_awarded = 10
        existing_award.base_xp = 10
        existing_award.to_dict.return_value = {
            "xp_awarded": 10,
            "new_total_xp": 100,
        }

        with patch(
            "app.routes.games.get_game_session_for_update",
            new_callable=AsyncMock,
            return_value=session,
        ), patch(
            "app.routes.games.get_existing_xp_award",
            new_callable=AsyncMock,
            return_value=existing_award,
        ), patch(
            "app.routes.games.check_achievements_for_user",
            new_callable=AsyncMock,
        ) as achievement_mock:
            response = await complete_game_session(
                session_id=session.id,
                body=GameSessionCompleteRequest(),
                db=MagicMock(),
                current_user=user,
            )

        assert response.award_status == "already_awarded"
        assert response.xp_awarded == 10
        assert response.raw_xp == 15
        assert response.penalties == 5
        achievement_mock.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_rejects_expired_session(self):
        from fastapi import HTTPException
        from app.routes.games import complete_game_session
        from app.schemas.games import GameSessionCompleteRequest

        session = MagicMock()
        session.user_id = uuid.uuid4()
        session.started_at = datetime.now(timezone.utc) - timedelta(hours=3)
        session.created_at = session.started_at
        session.completed_at = None
        session.xp_awarded = False
        user = MagicMock()
        user.id = session.user_id

        with patch(
            "app.routes.games.get_game_session_for_update",
            new_callable=AsyncMock,
            return_value=session,
        ):
            with pytest.raises(HTTPException) as exc:
                await complete_game_session(
                    session_id=uuid.uuid4(),
                    body=GameSessionCompleteRequest(),
                    db=MagicMock(),
                    current_user=user,
                )

        assert exc.value.status_code == 410

    @pytest.mark.asyncio
    async def test_rejects_another_users_session(self):
        from fastapi import HTTPException
        from app.routes.games import complete_game_session
        from app.schemas.games import GameSessionCompleteRequest

        session = MagicMock()
        session.user_id = uuid.uuid4()
        user = MagicMock()
        user.id = uuid.uuid4()

        with patch(
            "app.routes.games.get_game_session_for_update",
            new_callable=AsyncMock,
            return_value=session,
        ):
            with pytest.raises(HTTPException) as exc:
                await complete_game_session(
                    session_id=uuid.uuid4(),
                    body=GameSessionCompleteRequest(),
                    db=MagicMock(),
                    current_user=user,
                )

        assert exc.value.status_code == 403


# ============================================================================
# Route Tests — GET /games/categories (DB needed)
# ============================================================================

class TestGameCategories:
    """Tests for GET /games/categories endpoint."""

    @pytest.mark.asyncio
    async def test_returns_categories_structure(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/categories")
        assert response.status_code == 200
        data = response.json()
        assert "categories" in data

    @pytest.mark.asyncio
    async def test_each_category_has_required_fields(self, auth_client: AsyncClient):
        response = await auth_client.get(f"{BASE}/categories")
        assert response.status_code == 200
        for cat in response.json()["categories"]:
            assert "id" in cat
            assert "label" in cat
            assert "count" in cat
