"""
Tests for News API Routes — Phase 2

Tests cover:
- GET /news             — article list, CEFR filter, pagination, category
- GET /news/categories  — available categories
- GET /news/{id}/quiz   — article quiz
- Internal helpers: _estimate_cefr, _estimate_reading_time, _extract_highlight_words
- Provider fallback: NewsAPI → NewsData.io
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
import httpx
from fastapi import HTTPException
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
        yield AsyncMock()

    app.dependency_overrides[get_db] = mock_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()


# ============================================================================
# Unit Tests — _estimate_cefr
# ============================================================================

class TestEstimateCefrLevel:
    """Tests for CEFR level estimation from article text."""

    def test_empty_content_defaults_to_b1(self):
        from app.routes.news import _estimate_cefr

        article = {"content": "", "description": ""}
        assert _estimate_cefr(article) == "B1"

    def test_none_content_defaults_to_b1(self):
        from app.routes.news import _estimate_cefr

        article = {"content": None, "description": None}
        assert _estimate_cefr(article) == "B1"

    def test_very_simple_short_text_returns_a1(self):
        from app.routes.news import _estimate_cefr

        # Short words, few words → A1
        article = {"content": "I go to the big red cat and see a dog on the mat"}
        level = _estimate_cefr(article)
        assert level in ("A1", "A2")  # Low complexity

    def test_complex_long_text_returns_higher_level(self):
        from app.routes.news import _estimate_cefr

        # Long technical words, long text → C1/C2
        complex_text = " ".join([
            "The implementation of sophisticated computational algorithms requires"
            " comprehensive understanding of mathematical foundations and theoretical"
            " frameworks underlying contemporary engineering methodologies."
        ] * 20)
        article = {"content": complex_text}
        level = _estimate_cefr(article)
        assert level in ("C1", "C2")

    def test_falls_back_to_description_when_no_content(self):
        from app.routes.news import _estimate_cefr

        article = {"content": None, "description": "I go to school every morning"}
        level = _estimate_cefr(article)
        assert level in ("A1", "A2", "B1")

    def test_returns_valid_cefr_level(self):
        from app.routes.news import _estimate_cefr

        valid_levels = {"A1", "A2", "B1", "B2", "C1", "C2"}
        article = {"content": "The quick brown fox jumps over the lazy dog every single morning"}
        assert _estimate_cefr(article) in valid_levels

    def test_complexity_boundary_b1_to_b2(self):
        """complexity_score of 35-49 → B2."""
        from app.routes.news import _estimate_cefr

        # avg_word_length ~5, word_count ~500 → score = (5-3)*10 + (500/50) = 30
        article = {"content": " ".join(["learn study think class speak"] * 100)}
        level = _estimate_cefr(article)
        assert level in ("B1", "B2")


# ============================================================================
# Unit Tests — _estimate_reading_time
# ============================================================================

class TestEstimateReadingTime:
    """Tests for reading time estimation."""

    def test_minimum_1_minute(self):
        from app.routes.news import _estimate_reading_time

        article = {"content": "Short text"}
        assert _estimate_reading_time(article) == 1

    def test_empty_content_returns_1(self):
        from app.routes.news import _estimate_reading_time

        article = {"content": "", "description": ""}
        assert _estimate_reading_time(article) == 1

    def test_150_words_returns_1_minute(self):
        from app.routes.news import _estimate_reading_time

        article = {"content": " ".join(["word"] * 150)}
        assert _estimate_reading_time(article) == 1

    def test_300_words_returns_2_minutes(self):
        from app.routes.news import _estimate_reading_time

        article = {"content": " ".join(["word"] * 300)}
        assert _estimate_reading_time(article) == 2

    def test_600_words_returns_4_minutes(self):
        from app.routes.news import _estimate_reading_time

        article = {"content": " ".join(["word"] * 600)}
        assert _estimate_reading_time(article) == 4

    def test_uses_description_fallback(self):
        from app.routes.news import _estimate_reading_time

        article = {"content": None, "description": " ".join(["word"] * 300)}
        assert _estimate_reading_time(article) == 2


# ============================================================================
# Unit Tests — _extract_highlight_words
# ============================================================================

class TestExtractHighlightWords:
    """Tests for vocabulary extraction logic."""

    def test_empty_content_returns_empty(self):
        from app.routes.news import _extract_highlight_words

        assert _extract_highlight_words({"content": ""}) == []
        assert _extract_highlight_words({"content": None, "description": None}) == []

    def test_extracts_long_uncommon_words(self):
        from app.routes.news import _extract_highlight_words

        article = {"content": "The algorithm demonstrated unprecedented capabilities"}
        words = _extract_highlight_words(article)
        # "algorithm", "demonstrated", "unprecedented", "capabilities" are all > 7 chars
        assert len(words) > 0

    def test_excludes_common_long_words(self):
        from app.routes.news import _extract_highlight_words

        # These are in COMMON_LONG_WORDS
        article = {"content": "something everything everyone together important national"}
        words = _extract_highlight_words(article)
        assert "something" not in words
        assert "everyone" not in words

    def test_max_10_highlighted_words(self):
        from app.routes.news import _extract_highlight_words

        # Many unique uncommon long words
        long_words = [
            "algorithm", "spectacular", "configuration", "implementation",
            "authenticate", "unauthorized", "infrastructure", "crystallization",
            "comprehensive", "sophisticated", "unprecedented", "methodology",
        ]
        article = {"content": " ".join(long_words)}
        words = _extract_highlight_words(article)
        assert len(words) <= 10

    def test_result_is_sorted(self):
        from app.routes.news import _extract_highlight_words

        article = {"content": "spectacular algorithm configuration"}
        words = _extract_highlight_words(article)
        assert words == sorted(words)

    def test_short_words_excluded(self):
        from app.routes.news import _extract_highlight_words

        article = {"content": "cat dog run fly jump swim"}
        words = _extract_highlight_words(article)
        assert words == []

    def test_words_are_lowercase(self):
        from app.routes.news import _extract_highlight_words

        article = {"content": "Algorithm Implementation Configuration"}
        words = _extract_highlight_words(article)
        for w in words:
            assert w == w.lower()


class TestNewsUrlSafety:
    """Tests for server-side fetch URL guard."""

    @pytest.mark.parametrize(
        "url",
        [
            "ftp://example.com/image.jpg",
            "http://localhost/image.jpg",
            "http://127.0.0.1/image.jpg",
            "http://10.0.0.1/image.jpg",
        ],
    )
    def test_rejects_non_public_urls(self, url):
        from app.routes.news import _validate_public_http_url

        with pytest.raises(HTTPException):
            _validate_public_http_url(url)

    def test_rejects_host_if_any_resolved_ip_is_private(self, monkeypatch):
        from app.routes.news import _validate_public_http_url

        def fake_getaddrinfo(*args, **kwargs):
            return [
                (None, None, None, "", ("93.184.216.34", 443)),
                (None, None, None, "", ("10.0.0.1", 443)),
            ]

        monkeypatch.setattr("socket.getaddrinfo", fake_getaddrinfo)

        with pytest.raises(HTTPException):
            _validate_public_http_url("https://safe.example/image.jpg")

    @pytest.mark.asyncio
    async def test_rejects_redirect_to_private_url(self, monkeypatch):
        from app.routes.news import _get_public_url

        def fake_getaddrinfo(*args, **kwargs):
            return [(None, None, None, "", ("93.184.216.34", 443))]

        class RedirectClient:
            async def get(self, url, **kwargs):
                return httpx.Response(
                    302,
                    headers={"location": "http://127.0.0.1/private"},
                    request=httpx.Request("GET", url),
                )

        monkeypatch.setattr("socket.getaddrinfo", fake_getaddrinfo)

        with pytest.raises(HTTPException):
            await _get_public_url(RedirectClient(), "https://safe.example/image.jpg")

    @pytest.mark.asyncio
    async def test_stream_rejects_redirect_to_private_url(self, monkeypatch):
        from app.routes.news import _stream_public_url

        def fake_getaddrinfo(host, *args, **kwargs):
            address = "127.0.0.1" if host == "127.0.0.1" else "93.184.216.34"
            return [(None, None, None, "", (address, 443))]

        class RedirectClient:
            def build_request(self, method, url, **kwargs):
                return httpx.Request(method, url)

            async def send(self, request, stream=False):
                return httpx.Response(
                    302,
                    headers={"location": "http://127.0.0.1/private"},
                    request=request,
                )

        monkeypatch.setattr("socket.getaddrinfo", fake_getaddrinfo)

        with pytest.raises(HTTPException):
            await _stream_public_url(
                RedirectClient(),
                "https://safe.example/audio.mp3",
            )


# ============================================================================
# Route Tests — GET /news/categories
# ============================================================================

class TestGetCategories:
    """Tests for GET /news/categories endpoint."""

    @pytest.mark.asyncio
    async def test_returns_all_categories(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/news/categories")
        assert response.status_code == 200
        data = response.json()
        assert "categories" in data
        assert len(data["categories"]) == 8

    @pytest.mark.asyncio
    async def test_each_category_has_required_fields(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/news/categories")
        for cat in response.json()["categories"]:
            assert "id" in cat
            assert "label" in cat
            assert "icon" in cat

    @pytest.mark.asyncio
    async def test_includes_technology_category(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/news/categories")
        ids = [c["id"] for c in response.json()["categories"]]
        assert "technology" in ids
        assert "science" in ids
        assert "general" in ids


# ============================================================================
# Route Tests — GET /news
# ============================================================================

class TestGetNews:
    """Tests for GET /news endpoint."""

    @pytest.mark.asyncio
    async def test_invalid_cefr_level_returns_400(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/news?level=X2")
        assert response.status_code == 400
        assert "Invalid CEFR level" in response.json()["error"]["message"]

    @pytest.mark.asyncio
    async def test_valid_cefr_levels_accepted(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {"articles": [], "total_results": 0}
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            for level in ["A1", "A2", "B1", "B2", "C1", "C2"]:
                response = await no_db_client.get(f"/api/v1/news?level={level}")
                assert response.status_code == 200, f"Level {level} should be valid"

    @pytest.mark.asyncio
    async def test_page_out_of_range_returns_422(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/news?page=0")
        assert response.status_code == 422

        response = await no_db_client.get("/api/v1/news?page=11")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_page_size_out_of_range_returns_422(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/news?page_size=2")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_returns_articles_with_cefr_fields(self, no_db_client: AsyncClient):
        articles_data = [
            {
                "id": "art001",
                "title": "Tech advances in AI",
                "description": "New AI model released",
                "content": "The sophisticated artificial neural network implementation demonstrates unprecedented performance on standard benchmark evaluations in the field of computational linguistics and natural language processing.",
                "url": "https://example.com/article1",
                "image_url": "",
                "source_name": "TechNews",
                "author": "Jane Doe",
                "published_at": "2024-01-15T10:00:00Z",
                "category": "technology",
                "provider": "newsapi",
            }
        ]
        mock_result = MagicMock()
        mock_result.data = {"articles": articles_data, "total_results": 1}
        mock_result.source = "api"
        mock_result.is_stale = False

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get("/api/v1/news")

        assert response.status_code == 200
        data = response.json()
        assert "articles" in data
        assert "categories" in data
        assert "source" in data
        assert "page" in data

        if data["articles"]:
            article = data["articles"][0]
            assert "cefr_level" in article
            assert "reading_time_min" in article
            assert "highlighted_words" in article
            assert article["cefr_level"] in ["A1", "A2", "B1", "B2", "C1", "C2"]

    @pytest.mark.asyncio
    async def test_level_filter_applied_after_fetch(self, no_db_client: AsyncClient):
        """Articles not matching the requested CEFR level should be filtered out."""
        articles_data = [
            {
                "id": "art1",
                "title": "Simple",
                "content": "I go to school",
                "description": "",
                "url": "", "image_url": "", "source_name": "", "author": "",
                "published_at": "", "category": "general", "provider": "newsapi",
                "cefr_level": "A1",
            },
            {
                "id": "art2",
                "title": "Complex",
                "content": " ".join(["sophisticated complicated extraordinary"] * 100),
                "description": "",
                "url": "", "image_url": "", "source_name": "", "author": "",
                "published_at": "", "category": "general", "provider": "newsapi",
                "cefr_level": "C1",
            },
        ]
        mock_result = MagicMock()
        mock_result.data = {"articles": articles_data, "total_results": 2}
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get("/api/v1/news?level=A1")

        data = response.json()
        for article in data["articles"]:
            assert article["cefr_level"] == "A1"

    @pytest.mark.asyncio
    async def test_429_on_quota_exhausted(self, no_db_client: AsyncClient):
        from app.services.api_cache_service import QuotaExhaustedError

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.side_effect = QuotaExhaustedError(
                "newsapi", reset_time="2024-01-02T00:00:00Z"
            )
            MockCache.return_value = mock_cache

            response = await no_db_client.get("/api/v1/news")

        assert response.status_code == 429

    @pytest.mark.asyncio
    async def test_cache_key_includes_category_and_page(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {"articles": [], "total_results": 0}
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            await no_db_client.get("/api/v1/news?category=technology&page=2")

        call_kwargs = mock_cache.get_or_fetch.call_args.kwargs
        cache_key = call_kwargs.get("cache_key") or mock_cache.get_or_fetch.call_args.args[0]
        assert "cat:technology" in cache_key
        assert "p:2" in cache_key


# ============================================================================
# Route Tests — GET /news/{article_id}/quiz
# ============================================================================

class TestGetArticleQuiz:
    """Tests for GET /news/{article_id}/quiz endpoint."""

    @pytest.mark.asyncio
    async def test_returns_quiz_structure(self, no_db_client: AsyncClient):
        mock_quiz_data = {
            "questions": [
                {
                    "id": 1,
                    "type": "comprehension",
                    "question": "What is the main idea?",
                    "options": ["A", "B", "C", "D"],
                    "correct_index": 0,
                    "explanation": "Because A is correct",
                }
            ] * 5,
            "total_questions": 5,
            "xp_reward": 15,
        }
        mock_result = MagicMock()
        mock_result.data = mock_quiz_data
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get("/api/v1/news/article_abc123/quiz")

        assert response.status_code == 200
        data = response.json()
        assert "article_id" in data
        assert data["article_id"] == "article_abc123"
        assert "quiz" in data
        assert "source" in data

    @pytest.mark.asyncio
    async def test_quiz_cache_key_format(self, no_db_client: AsyncClient):
        """Cache key should be versioned so stale placeholder quizzes are bypassed."""
        mock_result = MagicMock()
        mock_result.data = {"questions": [], "total_questions": 0, "xp_reward": 15}
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            await no_db_client.get("/api/v1/news/myArticle001/quiz")

        call_kwargs = mock_cache.get_or_fetch.call_args.kwargs
        assert call_kwargs["cache_key"] == "news:quiz:v2:myArticle001"

    @pytest.mark.asyncio
    async def test_429_on_quota_error(self, no_db_client: AsyncClient):
        from app.services.api_cache_service import QuotaExhaustedError

        with patch("app.routes.news.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.side_effect = QuotaExhaustedError(
                "newsapi", reset_time="2024-01-02T00:00:00Z"
            )
            MockCache.return_value = mock_cache

            response = await no_db_client.get("/api/v1/news/article123/quiz")

        assert response.status_code == 429


# ============================================================================
# Unit Tests — _generate_quiz placeholder structure
# ============================================================================

class TestGenerateQuizStructure:
    """Tests for the quiz placeholder structure returned by _generate_quiz."""

    @pytest.mark.asyncio
    async def test_quiz_uses_article_context_when_available(self):
        from app.routes.news import _generate_quiz

        article = {
            "title": "Solar Panels Power Local School",
            "description": "Students learn from a new renewable energy project.",
            "content": (
                "A local school installed solar panels on the roof. "
                "The project reduces electricity costs and teaches students about renewable energy. "
                "Teachers said the panels will support science lessons throughout the year."
            ),
        }

        quiz = await _generate_quiz("solar_school", article=article)

        serialized = str(quiz).lower()
        assert "solar" in serialized
        assert "renewable" in serialized or "electricity" in serialized
        assert "option a" not in serialized
        assert "ai-generated" not in serialized

    @pytest.mark.asyncio
    async def test_quiz_falls_back_to_article_id_without_placeholders(self):
        from app.routes.news import _generate_quiz

        quiz = await _generate_quiz("climate_policy_2026")

        serialized = str(quiz).lower()
        assert "option a" not in serialized
        assert "ai-generated" not in serialized
        assert quiz["total_questions"] == len(quiz["questions"])

    @pytest.mark.asyncio
    async def test_quiz_has_5_questions(self):
        from app.routes.news import _generate_quiz

        quiz = await _generate_quiz("any_article_id")
        assert len(quiz["questions"]) == 5

    @pytest.mark.asyncio
    async def test_quiz_has_correct_xp_reward(self):
        from app.routes.news import _generate_quiz

        quiz = await _generate_quiz("any_article_id")
        assert quiz["xp_reward"] == 15

    @pytest.mark.asyncio
    async def test_quiz_total_questions_field(self):
        from app.routes.news import _generate_quiz

        quiz = await _generate_quiz("any_article_id")
        assert quiz["total_questions"] == 5

    @pytest.mark.asyncio
    async def test_each_question_has_required_fields(self):
        from app.routes.news import _generate_quiz

        quiz = await _generate_quiz("any_article_id")
        for q in quiz["questions"]:
            assert "id" in q
            assert "type" in q
            assert "question" in q
            assert "options" in q
            assert "correct_index" in q
            assert "explanation" in q
            assert len(q["options"]) == 4

    @pytest.mark.asyncio
    async def test_question_types_correct(self):
        from app.routes.news import _generate_quiz

        quiz = await _generate_quiz("any_article_id")
        types = [q["type"] for q in quiz["questions"]]
        assert types.count("comprehension") == 2
        assert types.count("vocabulary") == 2
        assert types.count("grammar") == 1

    @pytest.mark.asyncio
    async def test_correct_index_within_bounds(self):
        from app.routes.news import _generate_quiz

        quiz = await _generate_quiz("any_article_id")
        for q in quiz["questions"]:
            assert 0 <= q["correct_index"] < len(q["options"])


# ============================================================================
# Integration Tests — _fetch_from_newsapi
# ============================================================================

class TestFetchFromNewsApi:
    """Tests for NewsAPI.org fetcher with mocked HTTP."""

    @pytest.mark.asyncio
    async def test_filters_removed_articles(self):
        from app.routes.news import _fetch_from_newsapi

        mock_api_response = {
            "status": "ok",
            "totalResults": 2,
            "articles": [
                {
                    "title": "[Removed]",
                    "content": None,
                    "description": None,
                    "url": "",
                    "urlToImage": "",
                    "source": {"name": "Unknown"},
                    "author": None,
                    "publishedAt": "2024-01-01T00:00:00Z",
                },
                {
                    "title": "Real Article Title",
                    "content": "Real article content",
                    "description": "Description",
                    "url": "https://example.com",
                    "urlToImage": "https://example.com/img.jpg",
                    "source": {"name": "TechCrunch"},
                    "author": "John",
                    "publishedAt": "2024-01-01T10:00:00Z",
                },
            ],
        }

        with patch("app.routes.news.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.NEWSAPI_KEY = "fake_key"

            mock_resp = MagicMock()
            mock_resp.json.return_value = mock_api_response
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _fetch_from_newsapi("technology", 1, 10, None)

        assert len(result["articles"]) == 1
        assert result["articles"][0]["title"] == "Real Article Title"

    @pytest.mark.asyncio
    async def test_article_has_normalized_fields(self):
        from app.routes.news import _fetch_from_newsapi

        mock_api_response = {
            "status": "ok",
            "totalResults": 1,
            "articles": [
                {
                    "title": "Space Discovery",
                    "content": "Scientists found something amazing",
                    "description": "Brief description",
                    "url": "https://example.com/space",
                    "urlToImage": "https://example.com/img.jpg",
                    "source": {"name": "Science Daily"},
                    "author": "Dr. Smith",
                    "publishedAt": "2024-03-15T08:00:00Z",
                }
            ],
        }

        with patch("app.routes.news.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.NEWSAPI_KEY = "fake_key"

            mock_resp = MagicMock()
            mock_resp.json.return_value = mock_api_response
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _fetch_from_newsapi("science", 1, 10, None)

        article = result["articles"][0]
        required_fields = ["id", "title", "description", "content", "url",
                           "image_url", "source_name", "author", "published_at",
                           "category", "provider"]
        for field in required_fields:
            assert field in article, f"Missing field: {field}"
        assert article["provider"] == "newsapi"
        assert article["category"] == "science"

    @pytest.mark.asyncio
    async def test_raises_on_api_error_status(self):
        from app.routes.news import _fetch_from_newsapi

        with patch("app.routes.news.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.NEWSAPI_KEY = "fake_key"

            mock_resp = MagicMock()
            mock_resp.json.return_value = {
                "status": "error",
                "message": "apiKeyInvalid",
            }
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            with pytest.raises(Exception, match="NewsAPI error"):
                await _fetch_from_newsapi("general", 1, 10, None)

    @pytest.mark.asyncio
    async def test_uses_everything_endpoint_for_query(self):
        from app.routes.news import _fetch_from_newsapi

        with patch("app.routes.news.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.NEWSAPI_KEY = "fake_key"

            mock_resp = MagicMock()
            mock_resp.json.return_value = {
                "status": "ok", "totalResults": 0, "articles": []
            }
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            await _fetch_from_newsapi("general", 1, 10, query="climate change")

        call_args = mock_http.get.call_args
        url_called = call_args.args[0]
        params_called = call_args.kwargs.get("params", {})
        assert "everything" in url_called
        assert params_called.get("q") == "climate change"


# ============================================================================
# Integration Tests — fetch fallback behavior
# ============================================================================

class TestFetchNewsFallback:
    """Tests for NewsAPI → NewsData.io fallback logic."""

    @pytest.mark.asyncio
    async def test_503_when_no_keys_configured(self):
        from app.routes.news import _fetch_news

        with patch("app.routes.news.settings") as mock_settings:
            mock_settings.NEWSAPI_KEY = None
            mock_settings.NEWSDATA_KEY = None

            with pytest.raises(Exception):  # HTTPException 503
                await _fetch_news("general")

    @pytest.mark.asyncio
    async def test_falls_back_to_newsdata_when_newsapi_fails(self):
        from app.routes.news import _fetch_news

        newsdata_response = {
            "articles": [{"id": "fallback_1", "title": "Fallback Article"}],
            "total_results": 1,
        }

        with patch("app.routes.news.settings") as mock_settings, \
             patch("app.routes.news._fetch_from_newsapi") as mock_newsapi, \
             patch("app.routes.news._fetch_from_newsdata") as mock_newsdata:
            mock_settings.NEWSAPI_KEY = "key1"
            mock_settings.NEWSDATA_KEY = "key2"

            mock_newsapi.side_effect = Exception("NewsAPI.org is down")
            mock_newsdata.return_value = newsdata_response

            result = await _fetch_news("general")

        assert result["articles"][0]["id"] == "fallback_1"
        mock_newsapi.assert_called_once()
        mock_newsdata.assert_called_once()
