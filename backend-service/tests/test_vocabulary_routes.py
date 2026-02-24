"""
Tests for Vocabulary API Routes
/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/routes/vocabulary.py

Covers:
- GET  /api/v1/vocabulary/items              — list vocab items (public)
- GET  /api/v1/vocabulary/items/{id}         — get vocab item (public)
- GET  /api/v1/vocabulary/collection         — user vocab collection (auth)
- POST /api/v1/vocabulary/collection         — add to collection (auth, query param)
- POST /api/v1/vocabulary/collection/bulk    — bulk add (auth)
- GET  /api/v1/vocabulary/due                — due for review (auth)
- POST /api/v1/vocabulary/review/{id}        — submit review (auth)
- GET  /api/v1/vocabulary/stats              — vocab stats (auth)
- POST /api/v1/vocabulary/decks              — create deck (auth, query params)
- GET  /api/v1/vocabulary/decks              — list decks (auth)
"""

import pytest
import uuid
from datetime import datetime, date, timedelta
from typing import List
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport

BASE = "/api/v1/vocabulary"
VOCAB_ID = "00000000-0000-0000-0000-000000000050"
USER_VOCAB_ID = "00000000-0000-0000-0000-000000000060"


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
async def auth_client():
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    mock_result = MagicMock()
    mock_result.scalar.return_value = None
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


def _make_mock_vocab_item(vocab_id: str = VOCAB_ID):
    """Build a mock VocabularyItem."""
    item = MagicMock()
    item.id = uuid.UUID(vocab_id)
    item.word = "hello"
    item.definition = "A greeting"
    item.translation = {"vi": "xin chào"}
    item.part_of_speech = "interjection"
    item.pronunciation = "həˈləʊ"
    item.difficulty_level = "A1"
    item.audio_url = None
    item.examples = ["Hello, how are you?"]
    item.tags = None
    item.course_id = None
    item.lesson_id = None
    item.usage_frequency = 0
    item.created_at = datetime.utcnow()
    item.updated_at = datetime.utcnow()
    return item


def _make_mock_user_vocab():
    """Build a mock UserVocabulary."""
    uv = MagicMock()
    uv.id = uuid.UUID(USER_VOCAB_ID)
    uv.vocabulary_id = uuid.UUID(VOCAB_ID)
    uv.user_id = uuid.UUID("00000000-0000-0000-0000-000000000001")
    uv.status = "learning"
    uv.ease_factor = 2.5
    uv.interval = 1
    uv.streak = 0
    uv.repetitions = 0
    uv.next_review_date = datetime.utcnow()
    uv.last_reviewed_at = None
    uv.is_due = False
    uv.accuracy = 0.0
    uv.total_reviews = 0
    uv.correct_reviews = 0
    uv.longest_streak = 0
    uv.total_xp_earned = 0
    uv.notes = None
    uv.added_at = datetime.utcnow()
    return uv


# ============================================================================
# GET /api/v1/vocabulary/items  — List vocab items (public)
# ============================================================================

class TestGetVocabularyItems:
    """Tests for GET /api/v1/vocabulary/items."""

    @pytest.mark.asyncio
    async def test_returns_200_with_empty_list(self, no_auth_client: AsyncClient):
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_items", new=AsyncMock(return_value=[])):
            response = await no_auth_client.get(f"{BASE}/items")
        assert response.status_code == 200
        assert response.json() == []

    @pytest.mark.asyncio
    async def test_does_not_require_auth(self, no_auth_client: AsyncClient):
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_items", new=AsyncMock(return_value=[])):
            response = await no_auth_client.get(f"{BASE}/items")
        assert response.status_code != 401

    @pytest.mark.asyncio
    async def test_search_param_calls_search_method(self, no_auth_client: AsyncClient):
        mock_search = AsyncMock(return_value=[])
        with patch("app.crud.vocabulary.vocabulary_crud.search_vocabulary", new=mock_search):
            response = await no_auth_client.get(f"{BASE}/items?search=hello")
        assert response.status_code == 200
        mock_search.assert_called_once()

    @pytest.mark.asyncio
    async def test_limit_max_is_100(self, no_auth_client: AsyncClient):
        """limit > 100 should fail validation."""
        response = await no_auth_client.get(f"{BASE}/items?limit=101")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_limit_min_is_1(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/items?limit=0")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_difficulty_level_filter_is_forwarded(self, no_auth_client: AsyncClient):
        mock_get_items = AsyncMock(return_value=[])
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_items", new=mock_get_items):
            await no_auth_client.get(f"{BASE}/items?difficulty_level=B1")
        _, call_kwargs = mock_get_items.call_args
        assert call_kwargs.get("difficulty_level") == "B1"


# ============================================================================
# GET /api/v1/vocabulary/items/{id}  — Get single vocab item (public)
# ============================================================================

class TestGetVocabularyItem:
    """Tests for GET /api/v1/vocabulary/items/{vocabulary_id}."""

    @pytest.mark.asyncio
    async def test_returns_404_when_not_found(self, no_auth_client: AsyncClient):
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_item", new=AsyncMock(return_value=None)):
            response = await no_auth_client.get(f"{BASE}/items/{VOCAB_ID}")
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_returns_item_when_found(self, no_auth_client: AsyncClient):
        mock_item = _make_mock_vocab_item()
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_item", new=AsyncMock(return_value=mock_item)):
            response = await no_auth_client.get(f"{BASE}/items/{VOCAB_ID}")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_invalid_uuid_returns_422(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/items/not-a-uuid")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_does_not_require_auth(self, no_auth_client: AsyncClient):
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_item", new=AsyncMock(return_value=None)):
            response = await no_auth_client.get(f"{BASE}/items/{VOCAB_ID}")
        assert response.status_code != 401


# ============================================================================
# GET /api/v1/vocabulary/collection  — User vocabulary collection (auth)
# ============================================================================

class TestGetUserCollection:
    """Tests for GET /api/v1/vocabulary/collection."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/collection")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_with_empty_collection(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary_list", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/collection")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_items_and_total(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary_list", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/collection")
        data = response.json()
        assert "items" in data
        assert "total" in data

    @pytest.mark.asyncio
    async def test_invalid_status_returns_400(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary_list", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/collection?status=invalid_status")
        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_valid_status_learning_accepted(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary_list", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/collection?status=learning")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_valid_status_mastered_accepted(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary_list", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/collection?status=mastered")
        assert response.status_code == 200


# ============================================================================
# POST /api/v1/vocabulary/collection  — Add to collection (auth, query param)
# ============================================================================

class TestAddToCollection:
    """Tests for POST /api/v1/vocabulary/collection?vocabulary_id=<uuid>."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(
            f"{BASE}/collection", params={"vocabulary_id": VOCAB_ID}
        )
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_vocab_not_found(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_item", new=AsyncMock(return_value=None)):
            response = await client.post(
                f"{BASE}/collection", params={"vocabulary_id": VOCAB_ID}
            )
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_adds_to_collection_successfully(self, auth_client):
        client, _, _, _ = auth_client
        mock_item = _make_mock_vocab_item()
        mock_user_vocab = _make_mock_user_vocab()
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_item", new=AsyncMock(return_value=mock_item)), \
             patch("app.crud.vocabulary.vocabulary_crud.add_to_collection", new=AsyncMock(return_value=mock_user_vocab)):
            response = await client.post(
                f"{BASE}/collection", params={"vocabulary_id": VOCAB_ID}
            )
        assert response.status_code == 201

    @pytest.mark.asyncio
    async def test_missing_vocabulary_id_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(f"{BASE}/collection")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_invalid_uuid_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(
            f"{BASE}/collection", params={"vocabulary_id": "not-a-uuid"}
        )
        assert response.status_code == 422


# ============================================================================
# POST /api/v1/vocabulary/collection/bulk  — Bulk add to collection (auth)
# ============================================================================

class TestBulkAddToCollection:
    """Tests for POST /api/v1/vocabulary/collection/bulk."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        payload = {"vocabulary_ids": [VOCAB_ID]}
        response = await no_auth_client.post(f"{BASE}/collection/bulk", json=payload)
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_empty_list_when_no_valid_ids(self, auth_client):
        client, _, _, _ = auth_client
        # All IDs are invalid (not found), so they are skipped
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_item", new=AsyncMock(return_value=None)):
            response = await client.post(
                f"{BASE}/collection/bulk",
                json={"vocabulary_ids": [VOCAB_ID]},
            )
        assert response.status_code == 200
        assert response.json() == []

    @pytest.mark.asyncio
    async def test_bulk_adds_valid_items(self, auth_client):
        client, _, _, _ = auth_client
        mock_item = _make_mock_vocab_item()
        mock_user_vocab = _make_mock_user_vocab()
        with patch("app.crud.vocabulary.vocabulary_crud.get_vocabulary_item", new=AsyncMock(return_value=mock_item)), \
             patch("app.crud.vocabulary.vocabulary_crud.add_to_collection", new=AsyncMock(return_value=mock_user_vocab)):
            response = await client.post(
                f"{BASE}/collection/bulk",
                json={"vocabulary_ids": [VOCAB_ID]},
            )
        assert response.status_code == 200
        assert len(response.json()) == 1

    @pytest.mark.asyncio
    async def test_missing_body_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(f"{BASE}/collection/bulk", json={})
        assert response.status_code == 422


# ============================================================================
# GET /api/v1/vocabulary/due  — Due for review (auth)
# ============================================================================

class TestGetDueVocabulary:
    """Tests for GET /api/v1/vocabulary/due."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/due")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_with_no_due_items(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_due_vocabulary", new=AsyncMock(return_value=[])), \
             patch("app.crud.vocabulary.vocabulary_crud.count_due_vocabulary", new=AsyncMock(return_value=0)):
            response = await client.get(f"{BASE}/due")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_required_fields(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_due_vocabulary", new=AsyncMock(return_value=[])), \
             patch("app.crud.vocabulary.vocabulary_crud.count_due_vocabulary", new=AsyncMock(return_value=0)):
            response = await client.get(f"{BASE}/due")
        data = response.json()
        assert "items" in data
        assert "total_due" in data
        assert "daily_target" in data
        assert "progress_percentage" in data

    @pytest.mark.asyncio
    async def test_limit_param_accepted(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_due_vocabulary", new=AsyncMock(return_value=[])), \
             patch("app.crud.vocabulary.vocabulary_crud.count_due_vocabulary", new=AsyncMock(return_value=0)):
            response = await client.get(f"{BASE}/due?limit=10")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_limit_max_is_50(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.get(f"{BASE}/due?limit=51")
        assert response.status_code == 422


# ============================================================================
# POST /api/v1/vocabulary/review/{id}  — Submit review (auth)
# ============================================================================

class TestSubmitReview:
    """Tests for POST /api/v1/vocabulary/review/{user_vocabulary_id}."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(
            f"{BASE}/review/{USER_VOCAB_ID}", json={"quality": 4, "time_spent_ms": 2000}
        )
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_not_found(self, auth_client):
        client, mock_session, mock_result, _ = auth_client
        mock_result.scalar_one_or_none.return_value = None
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary", new=AsyncMock(return_value=None)):
            response = await client.post(
                f"{BASE}/review/{USER_VOCAB_ID}",
                json={"quality": 4, "time_spent_ms": 2000},
            )
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_returns_403_when_wrong_user(self, auth_client):
        client, mock_session, mock_result, mock_user = auth_client
        mock_user_vocab = _make_mock_user_vocab()
        mock_user_vocab.user_id = "00000000-0000-0000-0000-999999999999"  # different user
        mock_result.scalar_one_or_none.return_value = mock_user_vocab
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary", new=AsyncMock(return_value=None)):
            response = await client.post(
                f"{BASE}/review/{USER_VOCAB_ID}",
                json={"quality": 4, "time_spent_ms": 2000},
            )
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_submits_review_successfully(self, auth_client):
        client, mock_session, mock_result, mock_user = auth_client
        mock_user_vocab = _make_mock_user_vocab()
        mock_user_vocab.user_id = mock_user.id
        mock_result.scalar_one_or_none.return_value = mock_user_vocab

        updated_vocab = _make_mock_user_vocab()
        updated_vocab.streak = 1
        updated_vocab.interval = 3

        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary", new=AsyncMock(return_value=None)), \
             patch("app.crud.vocabulary.vocabulary_crud.submit_review", new=AsyncMock(return_value=updated_vocab)), \
             patch("app.services.check_achievements_for_user", new=AsyncMock(return_value=[])):
            response = await client.post(
                f"{BASE}/review/{USER_VOCAB_ID}",
                json={"quality": 4, "time_spent_ms": 2000},
            )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_missing_quality_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(
            f"{BASE}/review/{USER_VOCAB_ID}", json={"time_spent_ms": 2000}
        )
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_invalid_uuid_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(
            f"{BASE}/review/not-a-uuid", json={"quality": 3, "time_spent_ms": 1000}
        )
        assert response.status_code == 422


# ============================================================================
# GET /api/v1/vocabulary/stats  — Vocabulary stats (auth)
# ============================================================================

class TestGetVocabularyStats:
    """Tests for GET /api/v1/vocabulary/stats."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/stats")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200(self, auth_client):
        client, _, _, _ = auth_client
        mock_stats = {
            "total": 10,
            "learning": 5,
            "reviewing": 3,
            "mastered": 2,
            "due_for_review": 1,
            "total_xp": 50,
            "best_streak": 7,
        }
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary_stats", new=AsyncMock(return_value=mock_stats)):
            response = await client.get(f"{BASE}/stats")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_total_words(self, auth_client):
        client, _, _, _ = auth_client
        mock_stats = {
            "total": 10,
            "learning": 5,
            "reviewing": 3,
            "mastered": 2,
            "due_for_review": 1,
            "total_xp": 50,
            "best_streak": 7,
        }
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary_stats", new=AsyncMock(return_value=mock_stats)):
            response = await client.get(f"{BASE}/stats")
        data = response.json()
        assert "total" in data


# ============================================================================
# POST /api/v1/vocabulary/decks  — Create deck (auth, query params)
# ============================================================================

class TestCreateDeck:
    """Tests for POST /api/v1/vocabulary/decks?name=<name>."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(
            f"{BASE}/decks", params={"name": "Travel Phrases"}
        )
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_missing_name_returns_422(self, auth_client):
        client, _, _, _ = auth_client
        response = await client.post(f"{BASE}/decks")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_creates_deck_successfully(self, auth_client):
        client, _, _, _ = auth_client
        mock_deck = MagicMock()
        mock_deck.id = uuid.UUID("00000000-0000-0000-0000-000000000070")
        mock_deck.name = "Travel Phrases"
        mock_deck.description = "Words for travel"
        mock_deck.color = "#2196F3"
        mock_deck.created_at = datetime.utcnow()
        mock_deck.user_id = "00000000-0000-0000-0000-000000000001"
        mock_deck.word_count = 0
        with patch("app.crud.vocabulary.vocabulary_crud.create_deck", new=AsyncMock(return_value=mock_deck)):
            response = await client.post(
                f"{BASE}/decks",
                params={"name": "Travel Phrases", "description": "Words for travel"},
            )
        assert response.status_code == 201

    @pytest.mark.asyncio
    async def test_name_max_length_100(self, auth_client):
        """Name exceeding 100 chars fails validation."""
        client, _, _, _ = auth_client
        long_name = "A" * 101
        response = await client.post(f"{BASE}/decks", params={"name": long_name})
        assert response.status_code == 422


# ============================================================================
# GET /api/v1/vocabulary/decks  — List decks (auth)
# ============================================================================

class TestGetUserDecks:
    """Tests for GET /api/v1/vocabulary/decks."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/decks")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_with_empty_list(self, auth_client):
        client, _, _, _ = auth_client
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_decks", new=AsyncMock(return_value=[])):
            response = await client.get(f"{BASE}/decks")
        assert response.status_code == 200
        assert response.json() == []

    @pytest.mark.asyncio
    async def test_returns_user_decks(self, auth_client):
        client, _, _, _ = auth_client
        mock_deck = MagicMock()
        mock_deck.id = uuid.UUID("00000000-0000-0000-0000-000000000070")
        mock_deck.name = "Travel Phrases"
        mock_deck.description = "Words for travel"
        mock_deck.color = "#2196F3"
        mock_deck.created_at = datetime.utcnow()
        mock_deck.user_id = "00000000-0000-0000-0000-000000000001"
        mock_deck.word_count = 5
        with patch("app.crud.vocabulary.vocabulary_crud.get_user_decks", new=AsyncMock(return_value=[mock_deck])):
            response = await client.get(f"{BASE}/decks")
        assert response.status_code == 200
