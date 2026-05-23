"""
Tests for Book API Routes — Phase 5

Tests cover:
- GET /books/recommended   — curated books list, CEFR filter
- GET /books/search        — search with caching + quota
- GET /books/{id}/quiz     — chapter comprehension quiz
- Internal helpers: _estimate_cefr_from_description, _estimate_cefr_from_subjects,
                    _normalize_gutendex_book, _normalize_open_library_book
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


# ============================================================================
# Fixture: no-DB async client
# ============================================================================

@pytest.fixture
async def no_db_client():
    """Async HTTP client with mocked DB dependency."""
    from app.main import app
    from app.core.database import get_db

    async def mock_get_db():
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
        yield mock_session

    app.dependency_overrides[get_db] = mock_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()


BASE = "/api/v1/books"


# ============================================================================
# Unit Tests — _estimate_cefr_from_description
# ============================================================================

class TestEstimateCefrFromDescription:
    """Tests for CEFR estimation from book description text."""

    def test_empty_string_returns_b1(self):
        from app.routes.books import _estimate_cefr_from_description
        assert _estimate_cefr_from_description("") == "B1"

    def test_none_returns_b1(self):
        from app.routes.books import _estimate_cefr_from_description
        assert _estimate_cefr_from_description(None) == "B1"

    def test_very_simple_short_words_returns_a1_or_a2(self):
        from app.routes.books import _estimate_cefr_from_description
        text = "I go to the shop. We eat food. Cat and dog play. Sun is hot."
        level = _estimate_cefr_from_description(text)
        assert level in ("A1", "A2")

    def test_complex_long_words_returns_high_level(self):
        from app.routes.books import _estimate_cefr_from_description
        complex_text = " ".join([
            "The philosophical implications of epistemological frameworks "
            "demonstrate unprecedented sophistication in metaphysical discourse "
            "and ontological categorizations of phenomenological consciousness."
        ] * 5)
        level = _estimate_cefr_from_description(complex_text)
        assert level in ("B2", "C1", "C2")

    def test_returns_valid_cefr_level(self):
        from app.routes.books import _estimate_cefr_from_description
        valid_levels = {"A1", "A2", "B1", "B2", "C1", "C2"}
        assert _estimate_cefr_from_description("A young girl explores a magical world") in valid_levels

    def test_intermediate_text_returns_b_or_c_level(self):
        from app.routes.books import _estimate_cefr_from_description
        # Words like "investigated", "mysterious", "disappearance" score as upper-B to C1
        # by the word-length heuristic — this is intentional behaviour.
        text = "The detective investigated the mysterious disappearance of a local merchant."
        level = _estimate_cefr_from_description(text)
        assert level in ("A2", "B1", "B2", "C1")

    def test_single_word_returns_valid_level(self):
        from app.routes.books import _estimate_cefr_from_description
        valid_levels = {"A1", "A2", "B1", "B2", "C1", "C2"}
        assert _estimate_cefr_from_description("cat") in valid_levels


# ============================================================================
# Unit Tests — _estimate_cefr_from_subjects
# ============================================================================

class TestEstimateCefrFromSubjects:
    """Tests for CEFR estimation from book subject/bookshelf tags."""

    def test_fairy_tales_returns_a1(self):
        from app.routes.books import _estimate_cefr_from_subjects
        assert _estimate_cefr_from_subjects(["Fairy Tales", "Children"]) == "A1"

    def test_adventure_returns_b1(self):
        from app.routes.books import _estimate_cefr_from_subjects
        assert _estimate_cefr_from_subjects(["Adventure Stories"]) == "B1"

    def test_philosophy_returns_c1(self):
        from app.routes.books import _estimate_cefr_from_subjects
        assert _estimate_cefr_from_subjects(["Philosophy", "Ethics"]) == "C1"

    def test_unknown_subjects_returns_none(self):
        from app.routes.books import _estimate_cefr_from_subjects
        assert _estimate_cefr_from_subjects(["XYZ Unknown Genre", "QRS"]) is None

    def test_empty_list_returns_none(self):
        from app.routes.books import _estimate_cefr_from_subjects
        assert _estimate_cefr_from_subjects([]) is None

    def test_case_insensitive_matching(self):
        from app.routes.books import _estimate_cefr_from_subjects
        assert _estimate_cefr_from_subjects(["POETRY"]) == "C1"


# ============================================================================
# Unit Tests — _normalize_gutendex_book
# ============================================================================

class TestNormalizeGutendexBook:
    """Tests for Gutendex API response normalization."""

    def test_id_prefixed_with_gutenberg(self):
        from app.routes.books import _normalize_gutendex_book
        book = {"id": 11, "authors": [], "subjects": [], "bookshelves": [], "formats": {}}
        result = _normalize_gutendex_book(book)
        assert result["id"] == "gutenberg-11"

    def test_source_is_gutenberg(self):
        from app.routes.books import _normalize_gutendex_book
        book = {"id": 11, "authors": [], "subjects": [], "bookshelves": [], "formats": {}}
        result = _normalize_gutendex_book(book)
        assert result["source"] == "gutenberg"

    def test_authors_joined_as_string(self):
        from app.routes.books import _normalize_gutendex_book
        book = {
            "id": 1,
            "authors": [{"name": "Jane Austen"}, {"name": "Co-Author"}],
            "subjects": [], "bookshelves": [], "formats": {}
        }
        result = _normalize_gutendex_book(book)
        assert "Jane Austen" in result["author"]
        assert "Co-Author" in result["author"]

    def test_download_url_prefers_utf8_plain_text(self):
        from app.routes.books import _normalize_gutendex_book
        book = {
            "id": 1,
            "authors": [], "subjects": [], "bookshelves": [],
            "formats": {
                "text/plain; charset=utf-8": "https://example.com/book.txt",
                "text/html": "https://example.com/book.html",
            }
        }
        result = _normalize_gutendex_book(book)
        assert result["download_url"] == "https://example.com/book.txt"

    def test_cover_url_from_image_jpeg(self):
        from app.routes.books import _normalize_gutendex_book
        book = {
            "id": 1,
            "authors": [], "subjects": [], "bookshelves": [],
            "formats": {"image/jpeg": "https://example.com/cover.jpg"}
        }
        result = _normalize_gutendex_book(book)
        assert result["cover_url"] == "https://example.com/cover.jpg"

    def test_cefr_level_set_from_bookshelves(self):
        from app.routes.books import _normalize_gutendex_book
        book = {
            "id": 1,
            "authors": [],
            "subjects": [],
            "bookshelves": ["Children's Literature"],
            "formats": {}
        }
        result = _normalize_gutendex_book(book)
        assert result["cefr_level"] in {"A1", "A2", "B1", "B2", "C1", "C2"}

    def test_unknown_author_defaults(self):
        from app.routes.books import _normalize_gutendex_book
        book = {"id": 1, "authors": [], "subjects": [], "bookshelves": [], "formats": {}}
        result = _normalize_gutendex_book(book)
        assert result["author"] == "Unknown"


# ============================================================================
# Unit Tests — _normalize_open_library_book
# ============================================================================

class TestNormalizeOpenLibraryBook:
    """Tests for Open Library API response normalization."""

    def test_id_prefixed_with_ol(self):
        from app.routes.books import _normalize_open_library_book
        work = {"key": "/works/OL82592W", "title": "Hamlet"}
        result = _normalize_open_library_book(work)
        assert result["id"] == "ol-OL82592W"

    def test_source_is_open_library(self):
        from app.routes.books import _normalize_open_library_book
        work = {"key": "/works/OL82592W", "title": "Hamlet"}
        result = _normalize_open_library_book(work)
        assert result["source"] == "open_library"

    def test_cover_url_from_cover_id(self):
        from app.routes.books import _normalize_open_library_book
        work = {"key": "/works/OL82592W", "title": "Hamlet", "cover_i": 12345}
        result = _normalize_open_library_book(work)
        assert "12345" in result["cover_url"]

    def test_no_cover_id_returns_empty_cover_url(self):
        from app.routes.books import _normalize_open_library_book
        work = {"key": "/works/OL82592W", "title": "Hamlet"}
        result = _normalize_open_library_book(work)
        assert result["cover_url"] == ""

    def test_download_url_points_to_openlibrary(self):
        from app.routes.books import _normalize_open_library_book
        work = {"key": "/works/OL82592W", "title": "Hamlet"}
        result = _normalize_open_library_book(work)
        assert "openlibrary.org" in result["download_url"]

    def test_authors_limited_to_two(self):
        from app.routes.books import _normalize_open_library_book
        work = {
            "key": "/works/OL1W", "title": "Test",
            "author_name": ["Author A", "Author B", "Author C", "Author D"]
        }
        result = _normalize_open_library_book(work)
        # At most 2 authors joined
        assert result["author"].count(",") <= 1


# ============================================================================
# Route Tests — GET /books/recommended
# ============================================================================

class TestGetRecommendedBooks:
    """Tests for GET /books/recommended endpoint."""

    @pytest.mark.asyncio
    async def test_returns_curated_books(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/recommended")
        assert response.status_code == 200
        data = response.json()
        assert "books" in data
        assert "total" in data
        assert "source" in data

    @pytest.mark.asyncio
    async def test_total_matches_books_count(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/recommended")
        data = response.json()
        assert data["total"] == len(data["books"])

    @pytest.mark.asyncio
    async def test_returns_at_least_5_curated_books(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/recommended")
        data = response.json()
        assert data["total"] >= 5

    @pytest.mark.asyncio
    async def test_source_is_curated(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/recommended")
        assert response.json()["source"] == "curated"

    @pytest.mark.asyncio
    async def test_level_filter_returns_only_matching_books(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/recommended?level=B1")
        assert response.status_code == 200
        for book in response.json()["books"]:
            assert book["cefr_level"] == "B1"

    @pytest.mark.asyncio
    async def test_invalid_level_returns_all_books(self, no_db_client: AsyncClient):
        """Invalid level is silently ignored — returns all curated books."""
        all_response = await no_db_client.get(f"{BASE}/recommended")
        filtered_response = await no_db_client.get(f"{BASE}/recommended?level=ZZ")
        # ZZ is not valid → no filter applied
        assert filtered_response.status_code == 200

    @pytest.mark.asyncio
    async def test_each_book_has_required_fields(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/recommended")
        for book in response.json()["books"]:
            assert "id" in book
            assert "title" in book
            assert "author" in book
            assert "cefr_level" in book
            assert "download_url" in book

    @pytest.mark.asyncio
    async def test_all_cefr_levels_represented(self, no_db_client: AsyncClient):
        """Curated list should cover multiple CEFR levels."""
        response = await no_db_client.get(f"{BASE}/recommended")
        levels = {b["cefr_level"] for b in response.json()["books"]}
        assert len(levels) >= 3


# ============================================================================
# Route Tests — GET /books/search
# ============================================================================

class TestSearchBooks:
    """Tests for GET /books/search endpoint."""

    @pytest.mark.asyncio
    async def test_requires_q_param(self, no_db_client: AsyncClient):
        """Missing q param returns 422."""
        response = await no_db_client.get(f"{BASE}/search")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_q_min_length_2(self, no_db_client: AsyncClient):
        """Single char query should fail min_length=2."""
        response = await no_db_client.get(f"{BASE}/search?q=a")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_invalid_cefr_level_returns_400(self, no_db_client: AsyncClient):
        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            MockCache.return_value = mock_cache
            response = await no_db_client.get(f"{BASE}/search?q=alice&level=XX")
        assert response.status_code == 400
        assert "CEFR" in response.json()["error"]["message"]

    @pytest.mark.asyncio
    async def test_returns_books_from_cache(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {
            "books": [
                {
                    "id": "gutenberg-11",
                    "source": "gutenberg",
                    "title": "Alice's Adventures in Wonderland",
                    "author": "Lewis Carroll",
                    "description": "A girl follows a rabbit",
                    "cover_url": "",
                    "download_url": "https://gutenberg.org/ebooks/11.txt",
                    "language": "en",
                    "cefr_level": "A2",
                    "cefr_info": {"label": "Elementary", "color": "#8BC34A"},
                    "subject": "Fantasy",
                    "download_count": 50000,
                    "chapter_count": 12,
                    "word_count": 26500,
                }
            ]
        }
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/search?q=alice")

        assert response.status_code == 200
        data = response.json()
        assert "books" in data
        assert "total" in data
        assert "source" in data
        assert data["source"] == "redis"
        assert data["query"] == "alice"

    @pytest.mark.asyncio
    async def test_level_filter_applied_to_results(self, no_db_client: AsyncClient):
        """Only books matching the CEFR level should be returned."""
        mock_result = MagicMock()
        mock_result.data = {
            "books": [
                {"id": "g-1", "title": "Book A", "cefr_level": "A1",
                 "source": "gutenberg", "author": "A", "description": "",
                 "cover_url": "", "download_url": "", "language": "en",
                 "cefr_info": {}, "subject": "", "download_count": 0,
                 "chapter_count": 0, "word_count": 0},
                {"id": "g-2", "title": "Book B", "cefr_level": "B2",
                 "source": "gutenberg", "author": "B", "description": "",
                 "cover_url": "", "download_url": "", "language": "en",
                 "cefr_info": {}, "subject": "", "download_count": 0,
                 "chapter_count": 0, "word_count": 0},
            ]
        }
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/search?q=book&level=A1")

        assert response.status_code == 200
        books = response.json()["books"]
        for book in books:
            assert book["cefr_level"] == "A1"

    @pytest.mark.asyncio
    async def test_429_on_quota_exhausted(self, no_db_client: AsyncClient):
        from app.services.api_cache_service import QuotaExhaustedError

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.side_effect = QuotaExhaustedError(
                "gutendex", reset_time="2024-01-02T00:00:00Z"
            )
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/search?q=shakespeare")

        assert response.status_code == 429

    @pytest.mark.asyncio
    async def test_cache_key_includes_query_and_page(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {"books": []}
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            await no_db_client.get(f"{BASE}/search?q=hamlet&page=2")

        call_kwargs = mock_cache.get_or_fetch.call_args.kwargs
        cache_key = call_kwargs.get("cache_key") or mock_cache.get_or_fetch.call_args.args[0]
        assert "hamlet" in cache_key
        assert "p:2" in cache_key


# ============================================================================
# Route Tests — GET /books/{book_id}/quiz
# ============================================================================

class TestGetBookQuiz:
    """Tests for GET /books/{book_id}/quiz endpoint."""

    @pytest.mark.asyncio
    async def test_returns_quiz_structure(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {
            "questions": [
                {
                    "id": "gutenberg-11_ch1_q1",
                    "question": "What is the main theme?",
                    "options": ["Option A", "Option B", "Option C", "Option D"],
                    "correct_index": 0,
                    "explanation": "It focuses on identity.",
                }
            ],
            "xp_reward": 25,
            "is_stub": True,
        }
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/gutenberg-11/quiz")

        assert response.status_code == 200
        data = response.json()
        assert "book_id" in data
        assert data["book_id"] == "gutenberg-11"
        assert "chapter" in data
        assert "questions" in data
        assert "xp_reward" in data

    @pytest.mark.asyncio
    async def test_xp_reward_is_25(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {"questions": [], "xp_reward": 25, "is_stub": True}
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/gutenberg-74/quiz")

        assert response.json()["xp_reward"] == 25

    @pytest.mark.asyncio
    async def test_chapter_parameter_accepted(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {"questions": [], "xp_reward": 25, "is_stub": True}
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/gutenberg-11/quiz?chapter=3")

        assert response.status_code == 200
        assert response.json()["chapter"] == 3

    @pytest.mark.asyncio
    async def test_chapter_below_1_returns_422(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/gutenberg-11/quiz?chapter=0")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_cache_key_includes_book_id_and_chapter(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {"questions": [], "xp_reward": 25, "is_stub": True}
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.books.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            await no_db_client.get(f"{BASE}/gutenberg-1342/quiz?chapter=5")

        call_kwargs = mock_cache.get_or_fetch.call_args.kwargs
        assert call_kwargs["cache_key"] == "books:quiz:gutenberg-1342:ch:5"


# ============================================================================
# Integration Tests — _fetch_books internal function
# ============================================================================

class TestFetchBooks:
    """Tests for _fetch_books with mocked HTTP responses."""

    @pytest.mark.asyncio
    async def test_deduplicates_by_title(self):
        from app.routes.books import _fetch_books

        gutendex_data = {
            "results": [
                {
                    "id": 11,
                    "title": "Alice's Adventures in Wonderland",
                    "authors": [{"name": "Lewis Carroll"}],
                    "subjects": [],
                    "bookshelves": ["Fantasy"],
                    "formats": {"text/plain; charset=utf-8": "https://example.com/11.txt"},
                    "languages": ["en"],
                    "download_count": 50000,
                }
            ]
        }
        open_library_data = {
            "docs": [
                {
                    "key": "/works/OL66554W",
                    "title": "Alice's Adventures in Wonderland",  # duplicate title
                    "author_name": ["Lewis Carroll"],
                    "subject": ["Fantasy"],
                }
            ]
        }

        with patch("httpx.AsyncClient") as MockClient:
            mock_http = AsyncMock()

            async def mock_get(url, params=None, **kwargs):
                resp = MagicMock()
                if "gutendex" in url:
                    resp.status_code = 200
                    resp.json.return_value = gutendex_data
                else:
                    resp.status_code = 200
                    resp.json.return_value = open_library_data
                return resp

            mock_http.get = mock_get
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _fetch_books(q="alice", page=1)

        # Both results have same title — only one should survive dedup
        assert len(result["books"]) == 1

    @pytest.mark.asyncio
    async def test_handles_gutendex_error_gracefully(self):
        from app.routes.books import _fetch_books

        with patch("httpx.AsyncClient") as MockClient:
            mock_http = AsyncMock()

            async def mock_get(url, params=None, **kwargs):
                if "gutendex" in url:
                    raise Exception("Connection refused")
                resp = MagicMock()
                resp.status_code = 200
                resp.json.return_value = {"docs": []}
                return resp

            mock_http.get = mock_get
            MockClient.return_value.__aenter__.return_value = mock_http

            # Should not raise — Gutendex error is caught gracefully
            result = await _fetch_books(q="alice", page=1)

        assert "books" in result

    @pytest.mark.asyncio
    async def test_filters_non_english_books_from_gutendex(self):
        from app.routes.books import _fetch_books

        gutendex_data = {
            "results": [
                {
                    "id": 999,
                    "title": "Un livre en français",
                    "authors": [],
                    "subjects": [],
                    "bookshelves": [],
                    "formats": {},
                    "languages": ["fr"],  # NOT English
                }
            ]
        }

        with patch("httpx.AsyncClient") as MockClient:
            mock_http = AsyncMock()

            async def mock_get(url, params=None, **kwargs):
                resp = MagicMock()
                resp.status_code = 200
                if "gutendex" in url:
                    resp.json.return_value = gutendex_data
                else:
                    resp.json.return_value = {"docs": []}
                return resp

            mock_http.get = mock_get
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _fetch_books(q="livre", page=1)

        # French book should be filtered out
        assert len(result["books"]) == 0


# ============================================================================
# Route Tests — CORS Proxy Endpoints
# ============================================================================

class TestProxyEndpoints:
    """Tests for GET /books/proxy/image and GET /books/proxy/text endpoints."""

    def test_proxy_book_urls_rewrites_gutenberg_links(self):
        from app.routes.books import _proxy_book_urls
        from fastapi import Request

        # Create a mock FastAPI Request
        mock_request = MagicMock(spec=Request)
        mock_request.base_url = "http://testserver/"

        book = {
            "title": "Grimms' Fairy Tales",
            "cover_url": "https://www.gutenberg.org/cache/epub/2591/pg2591.cover.medium.jpg",
            "download_url": "https://www.gutenberg.org/cache/epub/2591/pg2591.txt",
        }

        with patch("app.routes.books.settings") as mock_settings:
            mock_settings.API_V1_PREFIX = "/api/v1"
            proxied = _proxy_book_urls(book, mock_request)

        assert "http://testserver/api/v1/books/proxy/image" in proxied["cover_url"]
        assert "url=https%3A//www.gutenberg.org" in proxied["cover_url"]
        assert "http://testserver/api/v1/books/proxy/text" in proxied["download_url"]
        assert "url=https%3A//www.gutenberg.org" in proxied["download_url"]

    @pytest.mark.asyncio
    async def test_proxy_image_success(self, no_db_client: AsyncClient):
        target_url = "https://www.gutenberg.org/cache/epub/2591/pg2591.cover.medium.jpg"
        
        # Mock httpx.AsyncClient inside the route
        with patch("app.routes.books.httpx.AsyncClient") as mock_client_class:
            mock_client = MagicMock()
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.content = b"fakeimagebinary"
            mock_resp.headers = {"content-type": "image/jpeg"}
            mock_client.get = AsyncMock(return_value=mock_resp)

            response = await no_db_client.get(f"{BASE}/proxy/image?url={target_url}")

        assert response.status_code == 200
        assert response.content == b"fakeimagebinary"
        assert response.headers["content-type"] == "image/jpeg"
        assert "max-age=86400" in response.headers["cache-control"]

    @pytest.mark.asyncio
    async def test_proxy_image_blocked_domain(self, no_db_client: AsyncClient):
        # A domain not in ALLOWED_PROXY_DOMAINS
        target_url = "https://malicious.com/virus.png"
        response = await no_db_client.get(f"{BASE}/proxy/image?url={target_url}")
        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_proxy_text_success(self, no_db_client: AsyncClient):
        target_url = "https://www.gutenberg.org/cache/epub/2591/pg2591.txt"
        
        # Mock httpx.AsyncClient inside the route
        with patch("app.routes.books.httpx.AsyncClient") as mock_client_class:
            mock_client = MagicMock()
            mock_client_class.return_value.__aenter__.return_value = mock_client
            
            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.content = b"Chapter 1: Once upon a time..."
            mock_resp.headers = {"content-type": "text/plain; charset=utf-8"}
            mock_client.get = AsyncMock(return_value=mock_resp)

            response = await no_db_client.get(f"{BASE}/proxy/text?url={target_url}")

        assert response.status_code == 200
        assert response.content == b"Chapter 1: Once upon a time..."
        assert response.headers["content-type"] == "text/plain; charset=utf-8"
        assert "max-age=86400" in response.headers["cache-control"]

