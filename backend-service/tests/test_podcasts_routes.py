"""
Tests for Podcast API Routes — Phase 4

Tests cover:
- GET /podcasts/curated     — curated podcasts grouped by CEFR
- GET /podcasts/search      — search with API key fallback and quota
- GET /podcasts/episodes    — RSS feed episode list (cached)
- POST /podcasts/transcript — placeholder transcript endpoint
- Internal helpers: _parse_duration, _strip_html, _estimate_cefr,
                    _group_curated_by_cefr, _build_podcastindex_headers,
                    _fetch_podcast_search
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport
from app.models.user import User


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


BASE = "/api/v1/podcasts"


# ============================================================================
# Unit Tests — _parse_duration
# ============================================================================

class TestParseDuration:
    """Tests for podcast duration string parser."""

    def test_hh_mm_ss_format(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration("1:30:00") == 5400   # 1h 30m

    def test_mm_ss_format(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration("5:45") == 345   # 5m 45s

    def test_bare_seconds(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration("120") == 120

    def test_empty_string_returns_zero(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration("") == 0

    def test_none_like_returns_zero(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration(None) == 0

    def test_invalid_string_returns_zero(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration("not-a-duration") == 0

    def test_zero_duration(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration("0:00") == 0

    def test_hh_mm_ss_large(self):
        from app.routes.podcasts import _parse_duration
        assert _parse_duration("2:00:00") == 7200


# ============================================================================
# Unit Tests — _strip_html
# ============================================================================

class TestStripHtml:
    """Tests for HTML tag removal helper."""

    def test_removes_basic_tags(self):
        from app.routes.podcasts import _strip_html
        result = _strip_html("<p>Hello <b>world</b></p>")
        assert result == "Hello world"

    def test_empty_string_returns_empty(self):
        from app.routes.podcasts import _strip_html
        assert _strip_html("") == ""

    def test_none_input_returns_empty(self):
        from app.routes.podcasts import _strip_html
        assert _strip_html(None) == ""

    def test_plain_text_unchanged(self):
        from app.routes.podcasts import _strip_html
        text = "No tags here"
        assert _strip_html(text) == text

    def test_removes_anchor_tags(self):
        from app.routes.podcasts import _strip_html
        result = _strip_html('<a href="http://example.com">Click here</a>')
        assert result == "Click here"

    def test_strips_whitespace(self):
        from app.routes.podcasts import _strip_html
        result = _strip_html("  <p>  Hello  </p>  ")
        assert "Hello" in result


# ============================================================================
# Unit Tests — _estimate_cefr
# ============================================================================

class TestEstimateCefr:
    """Tests for CEFR level estimation from podcast description."""

    def test_empty_string_returns_b1(self):
        from app.routes.podcasts import _estimate_cefr
        assert _estimate_cefr("") == "B1"

    def test_none_returns_b1(self):
        from app.routes.podcasts import _estimate_cefr
        assert _estimate_cefr(None) == "B1"

    def test_very_simple_text_returns_low_level(self):
        from app.routes.podcasts import _estimate_cefr
        level = _estimate_cefr("I go to school. We eat. Cat and dog.")
        assert level in ("A1", "A2")

    def test_complex_text_returns_high_level(self):
        from app.routes.podcasts import _estimate_cefr
        complex_text = " ".join([
            "The implementation of sophisticated algorithms requires comprehensive"
            " understanding of theoretical frameworks and mathematical foundations."
        ] * 10)
        level = _estimate_cefr(complex_text)
        assert level in ("C1", "C2")

    def test_returns_valid_cefr_level(self):
        from app.routes.podcasts import _estimate_cefr
        valid_levels = {"A1", "A2", "B1", "B2", "C1", "C2"}
        assert _estimate_cefr("Learning English through podcasts every day") in valid_levels


# ============================================================================
# Unit Tests — _group_curated_by_cefr
# ============================================================================

class TestGroupCuratedByCefr:
    """Tests for curated podcast CEFR band grouping."""

    def test_returns_three_bands(self):
        from app.routes.podcasts import _group_curated_by_cefr
        groups = _group_curated_by_cefr()
        assert len(groups) == 3

    def test_band_ids_are_correct(self):
        from app.routes.podcasts import _group_curated_by_cefr
        groups = _group_curated_by_cefr()
        ids = {g["id"] for g in groups}
        assert ids == {"A1-A2", "B1-B2", "C1-C2"}

    def test_each_band_has_podcast_ids(self):
        from app.routes.podcasts import _group_curated_by_cefr
        groups = _group_curated_by_cefr()
        for g in groups:
            assert "podcast_ids" in g
            assert isinstance(g["podcast_ids"], list)

    def test_a1_a2_band_has_entries(self):
        from app.routes.podcasts import _group_curated_by_cefr
        groups = _group_curated_by_cefr()
        a1_a2 = next(g for g in groups if g["id"] == "A1-A2")
        assert len(a1_a2["podcast_ids"]) >= 1

    def test_each_band_has_label(self):
        from app.routes.podcasts import _group_curated_by_cefr
        groups = _group_curated_by_cefr()
        for g in groups:
            assert "label" in g
            assert len(g["label"]) > 0


# ============================================================================
# Unit Tests — _build_podcastindex_headers
# ============================================================================

class TestBuildPodcastindexHeaders:
    """Tests for PodcastIndex HMAC-SHA1 auth header builder."""

    def test_returns_required_headers(self):
        from app.routes.podcasts import _build_podcastindex_headers
        with patch("app.routes.podcasts.settings") as mock_settings:
            mock_settings.PODCASTINDEX_KEY = "test_key"
            mock_settings.PODCASTINDEX_SECRET = "test_secret"
            headers = _build_podcastindex_headers()

        assert "X-Auth-Date" in headers
        assert "X-Auth-Key" in headers
        assert "Authorization" in headers
        assert "User-Agent" in headers

    def test_auth_key_matches_settings(self):
        from app.routes.podcasts import _build_podcastindex_headers
        with patch("app.routes.podcasts.settings") as mock_settings:
            mock_settings.PODCASTINDEX_KEY = "my_api_key"
            mock_settings.PODCASTINDEX_SECRET = "my_secret"
            headers = _build_podcastindex_headers()

        assert headers["X-Auth-Key"] == "my_api_key"

    def test_authorization_is_hex_string(self):
        from app.routes.podcasts import _build_podcastindex_headers
        with patch("app.routes.podcasts.settings") as mock_settings:
            mock_settings.PODCASTINDEX_KEY = "key"
            mock_settings.PODCASTINDEX_SECRET = "secret"
            headers = _build_podcastindex_headers()

        # SHA1 produces 40-char hex string
        assert len(headers["Authorization"]) == 40
        assert all(c in "0123456789abcdef" for c in headers["Authorization"])

    def test_x_auth_date_is_numeric_string(self):
        from app.routes.podcasts import _build_podcastindex_headers
        with patch("app.routes.podcasts.settings") as mock_settings:
            mock_settings.PODCASTINDEX_KEY = "k"
            mock_settings.PODCASTINDEX_SECRET = "s"
            headers = _build_podcastindex_headers()

        assert headers["X-Auth-Date"].isdigit()


# ============================================================================
# Route Tests — GET /podcasts/curated
# ============================================================================

class TestGetCuratedPodcasts:
    """Tests for GET /podcasts/curated endpoint."""

    @pytest.mark.asyncio
    async def test_returns_curated_structure(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/curated")
        assert response.status_code == 200
        data = response.json()
        assert "podcasts" in data
        assert "categories" in data

    @pytest.mark.asyncio
    async def test_returns_all_curated_podcasts(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/curated")
        assert response.status_code == 200
        data = response.json()
        assert len(data["podcasts"]) >= 5  # At least 5 curated podcasts

    @pytest.mark.asyncio
    async def test_each_podcast_has_required_fields(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/curated")
        assert response.status_code == 200
        for podcast in response.json()["podcasts"]:
            assert "id" in podcast
            assert "title" in podcast
            assert "author" in podcast
            assert "feed_url" in podcast
            assert "cefr_level" in podcast

    @pytest.mark.asyncio
    async def test_categories_have_three_bands(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/curated")
        assert response.status_code == 200
        categories = response.json()["categories"]
        assert len(categories) == 3

    @pytest.mark.asyncio
    async def test_cefr_levels_are_valid(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/curated")
        valid = {"A1", "A2", "B1", "B2", "C1", "C2"}
        for podcast in response.json()["podcasts"]:
            assert podcast["cefr_level"] in valid

    @pytest.mark.asyncio
    async def test_covers_all_cefr_bands(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/curated")
        levels = {p["cefr_level"] for p in response.json()["podcasts"]}
        # Must have representation from at least 3 different levels
        assert len(levels) >= 3

    @pytest.mark.asyncio
    async def test_no_db_needed(self, no_db_client: AsyncClient):
        """Curated endpoint requires no external calls or DB."""
        response = await no_db_client.get(f"{BASE}/curated")
        assert response.status_code == 200


# ============================================================================
# Route Tests — GET /podcasts/search
# ============================================================================

class TestSearchPodcasts:
    """Tests for GET /podcasts/search endpoint."""

    @pytest.mark.asyncio
    async def test_requires_q_param(self, no_db_client: AsyncClient):
        """Missing q should return 422."""
        response = await no_db_client.get(f"{BASE}/search")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_falls_back_to_curated_when_no_api_key(self, no_db_client: AsyncClient):
        """When PODCASTINDEX_KEY is None, return curated fallback."""
        with patch("app.routes.podcasts.settings") as mock_settings:
            mock_settings.PODCASTINDEX_KEY = None
            mock_settings.PODCASTINDEX_SECRET = None
            response = await no_db_client.get(f"{BASE}/search?q=english")

        assert response.status_code == 200
        data = response.json()
        assert data["source"] == "curated_fallback"
        assert "podcasts" in data
        assert "note" in data

    @pytest.mark.asyncio
    async def test_returns_search_results_from_cache(self, no_db_client: AsyncClient):
        """With valid API key and cached result, return cached data."""
        mock_result = MagicMock()
        mock_result.data = {
            "podcasts": [
                {
                    "id": "pod001",
                    "title": "Learn English Now",
                    "author": "ESL Teacher",
                    "description": "English lessons for beginners",
                    "feed_url": "https://example.com/feed.rss",
                    "artwork_url": "https://example.com/img.jpg",
                    "episode_count": 50,
                    "categories": ["education"],
                    "language": "en",
                }
            ]
        }
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.podcasts.settings") as mock_settings, \
             patch("app.routes.podcasts.APICacheService") as MockCache:
            mock_settings.PODCASTINDEX_KEY = "fake_key"
            mock_settings.PODCASTINDEX_SECRET = "fake_secret"
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/search?q=english")

        assert response.status_code == 200
        data = response.json()
        assert "podcasts" in data
        assert "source" in data
        assert data["source"] == "redis"

    @pytest.mark.asyncio
    async def test_429_on_quota_exhausted(self, no_db_client: AsyncClient):
        from app.services.api_cache_service import QuotaExhaustedError

        with patch("app.routes.podcasts.settings") as mock_settings, \
             patch("app.routes.podcasts.APICacheService") as MockCache:
            mock_settings.PODCASTINDEX_KEY = "fake_key"
            mock_settings.PODCASTINDEX_SECRET = "fake_secret"
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.side_effect = QuotaExhaustedError(
                "podcastindex", reset_time="2024-01-02T00:00:00Z"
            )
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/search?q=english")

        assert response.status_code == 429

    @pytest.mark.asyncio
    async def test_max_results_validation(self, no_db_client: AsyncClient):
        """max_results > 50 should fail validation."""
        with patch("app.routes.podcasts.settings") as mock_settings:
            mock_settings.PODCASTINDEX_KEY = None
            mock_settings.PODCASTINDEX_SECRET = None
            response = await no_db_client.get(f"{BASE}/search?q=english&max_results=100")

        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_cefr_level_estimated_when_missing(self, no_db_client: AsyncClient):
        """Podcasts without cefr_level should get one estimated."""
        mock_result = MagicMock()
        mock_result.data = {
            "podcasts": [
                {
                    "id": "pod001",
                    "title": "Test Podcast",
                    "author": "Author",
                    "description": "A great English learning podcast for students",
                    "feed_url": "https://example.com/feed.rss",
                    "category": [],
                    # No cefr_level → should be estimated
                }
            ]
        }
        mock_result.source = "api"
        mock_result.is_stale = False

        with patch("app.routes.podcasts.settings") as mock_settings, \
             patch("app.routes.podcasts.APICacheService") as MockCache:
            mock_settings.PODCASTINDEX_KEY = "fake_key"
            mock_settings.PODCASTINDEX_SECRET = "fake_secret"
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/search?q=english")

        assert response.status_code == 200
        for podcast in response.json()["podcasts"]:
            assert "cefr_level" in podcast
            assert podcast["cefr_level"] in {"A1", "A2", "B1", "B2", "C1", "C2"}


# ============================================================================
# Route Tests — GET /podcasts/episodes
# ============================================================================

class TestGetPodcastEpisodes:
    """Tests for GET /podcasts/episodes endpoint."""

    @pytest.mark.asyncio
    async def test_requires_feed_url_param(self, no_db_client: AsyncClient):
        """Missing feed_url should return 422."""
        response = await no_db_client.get(f"{BASE}/episodes")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_returns_episode_list(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {
            "episodes": [
                {
                    "guid": "ep001",
                    "title": "Episode 1 — Greetings",
                    "audio_url": "https://example.com/ep1.mp3",
                    "duration_seconds": 360,
                    "published_at": "Mon, 15 Jan 2024 10:00:00 +0000",
                    "description": "Learn how to greet people in English",
                    "episode_number": 1,
                    "image_url": None,
                    "cefr_level": None,
                }
            ],
            "podcast_title": "Learn English Fast",
            "podcast_description": "Daily English lessons",
        }
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.podcasts.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(
                f"{BASE}/episodes?feed_url=https://example.com/feed.rss"
            )

        assert response.status_code == 200
        data = response.json()
        assert "episodes" in data
        assert "podcast_title" in data
        assert "feed_url" in data
        assert "source" in data
        assert len(data["episodes"]) == 1

    @pytest.mark.asyncio
    async def test_episode_has_required_fields(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {
            "episodes": [
                {
                    "guid": "ep001",
                    "title": "Episode 1",
                    "audio_url": "https://example.com/ep1.mp3",
                    "duration_seconds": 600,
                    "published_at": "2024-01-01T10:00:00Z",
                    "description": "Test episode",
                    "episode_number": 1,
                }
            ],
            "podcast_title": "Test Podcast",
            "podcast_description": "",
        }
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.podcasts.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(
                f"{BASE}/episodes?feed_url=https://example.com/feed.rss"
            )

        assert response.status_code == 200
        episode = response.json()["episodes"][0]
        assert "guid" in episode
        assert "title" in episode
        assert "audio_url" in episode
        assert "duration_seconds" in episode

    @pytest.mark.asyncio
    async def test_limit_validation_max_50(self, no_db_client: AsyncClient):
        """limit > 50 should fail validation."""
        response = await no_db_client.get(
            f"{BASE}/episodes?feed_url=https://example.com/feed.rss&limit=100"
        )
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_limit_validation_min_1(self, no_db_client: AsyncClient):
        """limit < 1 should fail validation."""
        response = await no_db_client.get(
            f"{BASE}/episodes?feed_url=https://example.com/feed.rss&limit=0"
        )
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_429_on_quota_error(self, no_db_client: AsyncClient):
        from app.services.api_cache_service import QuotaExhaustedError

        with patch("app.routes.podcasts.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.side_effect = QuotaExhaustedError(
                "rss_feed", reset_time="2024-01-02T00:00:00Z"
            )
            MockCache.return_value = mock_cache

            response = await no_db_client.get(
                f"{BASE}/episodes?feed_url=https://example.com/feed.rss"
            )

        assert response.status_code == 429

    @pytest.mark.asyncio
    async def test_cache_key_includes_feed_url(self, no_db_client: AsyncClient):
        """Cache key should include a hash of the feed_url."""
        mock_result = MagicMock()
        mock_result.data = {"episodes": [], "podcast_title": "", "podcast_description": ""}
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.podcasts.APICacheService") as MockCache:
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            await no_db_client.get(
                f"{BASE}/episodes?feed_url=https://feeds.npr.org/510298/podcast.xml"
            )

        call_kwargs = mock_cache.get_or_fetch.call_args.kwargs
        assert "cache_key" in call_kwargs
        assert call_kwargs["cache_key"].startswith("podcasts:episodes:")


# ============================================================================
# Route Tests — POST /podcasts/transcript
# ============================================================================

class TestTranscriptEndpoint:
    """Tests for POST /podcasts/transcript endpoint."""

    @pytest.mark.asyncio
    async def test_requires_authentication(self, no_db_client: AsyncClient):
        response = await no_db_client.post(
            f"{BASE}/transcript",
            json={
                "feed_url": "https://example.com/feed.rss",
                "episode_guid": "ep001",
                "audio_url": "https://example.com/ep1.mp3",
            },
        )
        assert response.status_code == 401
        assert response.json()["error"]["message"] == "Not authenticated"

    @pytest.mark.asyncio
    async def test_returns_cached_transcript(self, no_db_client: AsyncClient):
        from app.services.api_cache_service import CacheResult
        from app.core.dependencies import get_current_user
        from app.main import app
        from app.models.user import User
        import uuid

        mock_user = User(id=uuid.uuid4(), username="testuser", email="test@example.com")
        async def mock_get_current_user():
            return mock_user

        app.dependency_overrides[get_current_user] = mock_get_current_user
        
        mock_cache_result = CacheResult(
            data={"transcript": "This is a mock podcast transcript."},
            source="redis",
            is_stale=False,
        )
        
        try:
            with patch("app.routes.podcasts.APICacheService") as MockCache:
                mock_cache = AsyncMock()
                mock_cache.get_or_fetch.return_value = mock_cache_result
                MockCache.return_value = mock_cache
                
                response = await no_db_client.post(
                    f"{BASE}/transcript",
                    json={
                        "feed_url": "https://example.com/feed.rss",
                        "episode_guid": "ep001",
                        "audio_url": "https://example.com/ep1.mp3",
                    },
                    headers={"Authorization": "Bearer fake_token"},
                )
        finally:
            app.dependency_overrides.pop(get_current_user, None)
            
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "completed"
        assert data["transcript"] == "This is a mock podcast transcript."
        assert data["feed_url"] == "https://example.com/feed.rss"
        assert data["episode_guid"] == "ep001"

    @pytest.mark.asyncio
    async def test_cache_miss_downloads_and_transcribes(
        self, no_db_client: AsyncClient
    ):
        from app.core.dependencies import get_current_user
        from app.main import app
        from app.models.user import User
        import uuid

        mock_user = User(id=uuid.uuid4(), username="testuser", email="test@example.com")
        async def mock_get_current_user():
            return mock_user

        app.dependency_overrides[get_current_user] = mock_get_current_user
        
        async def mock_get_or_fetch(cache_key, api_name, fetch_fn, **kwargs):
            from app.services.api_cache_service import CacheResult
            data = await fetch_fn()
            return CacheResult(data=data, source="api", is_stale=False)

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"Content-Length": "100"}
        async def mock_iter_bytes(*args, **kwargs):
            yield b"mock_audio_data"
        mock_response.iter_bytes = mock_iter_bytes
        
        mock_stream = AsyncMock()
        mock_stream.__aenter__.return_value = mock_response
        
        mock_transcribe = AsyncMock(return_value={"text": "Hello world from transcript"})
        
        try:
            with patch("app.routes.podcasts.APICacheService") as MockCache, \
                 patch("httpx.AsyncClient.stream", return_value=mock_stream), \
                 patch("app.routes.podcasts.AIServiceClient.transcribe_audio", mock_transcribe):
                
                mock_cache = AsyncMock()
                mock_cache.get_or_fetch.side_effect = mock_get_or_fetch
                MockCache.return_value = mock_cache
                
                response = await no_db_client.post(
                    f"{BASE}/transcript",
                    json={
                        "feed_url": "https://example.com/feed.rss",
                        "episode_guid": "ep001",
                        "audio_url": "https://example.com/ep1.mp3",
                    },
                    headers={"Authorization": "Bearer fake_token"},
                )
        finally:
            app.dependency_overrides.pop(get_current_user, None)
            
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "completed"
        assert data["transcript"] == "Hello world from transcript"
        assert data["feed_url"] == "https://example.com/feed.rss"
        assert data["episode_guid"] == "ep001"




# ============================================================================
# Integration Tests — _fetch_podcast_search internal function
# ============================================================================

class TestFetchPodcastSearch:
    """Tests for _fetch_podcast_search internal function with mocked HTTP."""

    @pytest.mark.asyncio
    async def test_normalizes_api_response(self):
        from app.routes.podcasts import _fetch_podcast_search

        mock_api_response = {
            "status": "true",
            "feeds": [
                {
                    "podcastGuid": "guid-001",
                    "title": "English Learning Podcast",
                    "author": "ESL Teacher",
                    "description": "<p>Learn English fast</p>",
                    "url": "https://example.com/feed.rss",
                    "artwork": "https://example.com/img.jpg",
                    "episodeCount": 120,
                    "categories": {1: "Education", 2: "Language Learning"},
                    "language": "en",
                }
            ],
        }

        with patch("app.routes.podcasts.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.PODCASTINDEX_KEY = "key"
            mock_settings.PODCASTINDEX_SECRET = "secret"

            mock_resp = MagicMock()
            mock_resp.json.return_value = mock_api_response
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _fetch_podcast_search(q="english", max_results=10)

        assert "podcasts" in result
        assert len(result["podcasts"]) == 1
        podcast = result["podcasts"][0]
        assert podcast["id"] == "guid-001"
        assert podcast["title"] == "English Learning Podcast"
        assert podcast["feed_url"] == "https://example.com/feed.rss"

    @pytest.mark.asyncio
    async def test_raises_on_podcastindex_error_status(self):
        from app.routes.podcasts import _fetch_podcast_search

        with patch("app.routes.podcasts.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.PODCASTINDEX_KEY = "key"
            mock_settings.PODCASTINDEX_SECRET = "secret"

            mock_resp = MagicMock()
            mock_resp.json.return_value = {
                "status": "false",
                "description": "Unauthorized",
            }
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            with pytest.raises(Exception, match="PodcastIndex error"):
                await _fetch_podcast_search(q="english", max_results=5)

    @pytest.mark.asyncio
    async def test_empty_feeds_returns_empty_list(self):
        from app.routes.podcasts import _fetch_podcast_search

        with patch("app.routes.podcasts.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.PODCASTINDEX_KEY = "key"
            mock_settings.PODCASTINDEX_SECRET = "secret"

            mock_resp = MagicMock()
            mock_resp.json.return_value = {"status": "true", "feeds": []}
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _fetch_podcast_search(q="zzz_nonexistent", max_results=10)

        assert result["podcasts"] == []
