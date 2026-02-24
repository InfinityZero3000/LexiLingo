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
        assert data["game"] == "fill_blank"
        assert "questions" in data
        assert "timer_seconds_per_question" in data
        assert "total" in data

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
        assert data["game"] == "grammar_quiz"
        assert "questions" in data
        assert "timer_seconds_per_question" in data
        assert "total" in data
        assert "cefr_level" in data

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
        response = await auth_client.get(f"{BASE}/word-scramble?level=A1&count=3")
        assert response.status_code == 200
        data = response.json()
        assert data["game"] == "word_scramble"
        assert "words" in data
        assert "timer_seconds" in data
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
        assert "word_id" in data
        assert "word" in data
        assert "category" in data
        assert "hint" in data
        assert "definition" in data
        assert "letter_count" in data
        assert "xp_value" in data
        assert "cefr_level" in data

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
        assert data["game"] == "matching"
        assert "pairs" in data
        assert "words_column" in data
        assert "definitions_column" in data
        assert "timer_seconds" in data
        assert "total_pairs" in data

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
