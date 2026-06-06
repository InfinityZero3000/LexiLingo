"""
Tests for YouTube API Routes — Phase 1

Tests cover:
- GET /youtube/channels       — curated channels, category filter
- GET /youtube/search         — search with quota management + caching
- GET /youtube/captions/{id}  — caption fetch + parse
- GET /youtube/channels/{id}/videos — channel videos
- Internal helpers: _parse_json3_captions, _estimate_cefr (import via news)
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


# ============================================================================
# Fixture: no-DB async client (routes that mock APICacheService don't need DB)
# ============================================================================

@pytest.fixture
async def no_db_client():
    """
    Async HTTP client that overrides DB dependency with a mock.
    Use this for route tests that mock APICacheService / no SQL needed.
    """
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
# Unit Tests — Internal Helpers (no HTTP needed)
# ============================================================================

class TestParseJson3Captions:
    """Tests for _parse_json3_captions helper function."""

    def test_parse_normal_events(self):
        from app.routes.youtube import _parse_json3_captions

        data = {
            "events": [
                {
                    "tStartMs": 1000,
                    "dDurationMs": 2000,
                    "segs": [{"utf8": "Hello "}, {"utf8": "world"}],
                },
                {
                    "tStartMs": 4000,
                    "dDurationMs": 1500,
                    "segs": [{"utf8": "This is a test"}],
                },
            ]
        }
        segments = _parse_json3_captions(data)

        assert len(segments) == 2
        assert segments[0]["start_ms"] == 1000
        assert segments[0]["end_ms"] == 3000
        assert segments[0]["text"] == "Hello world"
        assert segments[1]["start_ms"] == 4000
        assert segments[1]["end_ms"] == 5500
        assert segments[1]["text"] == "This is a test"

    def test_skip_empty_and_newline_only_events(self):
        from app.routes.youtube import _parse_json3_captions

        data = {
            "events": [
                {"tStartMs": 0, "dDurationMs": 500, "segs": [{"utf8": "\n"}]},
                {"tStartMs": 100, "dDurationMs": 500, "segs": [{"utf8": ""}]},
                {"tStartMs": 200, "dDurationMs": 1000, "segs": [{"utf8": "Valid text"}]},
            ]
        }
        segments = _parse_json3_captions(data)
        assert len(segments) == 1
        assert segments[0]["text"] == "Valid text"

    def test_empty_events_list(self):
        from app.routes.youtube import _parse_json3_captions

        segments = _parse_json3_captions({"events": []})
        assert segments == []

    def test_missing_events_key(self):
        from app.routes.youtube import _parse_json3_captions

        segments = _parse_json3_captions({})
        assert segments == []

    def test_missing_duration_defaults_to_zero(self):
        from app.routes.youtube import _parse_json3_captions

        data = {
            "events": [
                {
                    "tStartMs": 5000,
                    "segs": [{"utf8": "No duration"}],
                }
            ]
        }
        segments = _parse_json3_captions(data)
        assert len(segments) == 1
        assert segments[0]["start_ms"] == 5000
        assert segments[0]["end_ms"] == 5000  # 5000 + 0

    def test_multiple_segs_concatenated(self):
        from app.routes.youtube import _parse_json3_captions

        data = {
            "events": [
                {
                    "tStartMs": 1000,
                    "dDurationMs": 2000,
                    "segs": [
                        {"utf8": "Part1"},
                        {"utf8": " "},
                        {"utf8": "Part2"},
                        {"utf8": " "},
                        {"utf8": "Part3"},
                    ],
                }
            ]
        }
        segments = _parse_json3_captions(data)
        assert segments[0]["text"] == "Part1 Part2 Part3"


# ============================================================================
# Route Tests — GET /youtube/channels
# ============================================================================

BASE = "/api/v1/youtube"


class TestGetCuratedChannels:
    """Tests for GET /youtube/channels endpoint."""

    @pytest.mark.asyncio
    async def test_returns_all_channels_no_filter(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/youtube/channels")
        assert response.status_code == 200
        data = response.json()
        assert "channels" in data
        assert "total" in data
        assert data["total"] == len(data["channels"])
        assert data["total"] >= 6  # At least 6 curated channels

    @pytest.mark.asyncio
    async def test_filter_by_valid_category(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/youtube/channels?category=general")
        assert response.status_code == 200
        data = response.json()
        for ch in data["channels"]:
            assert ch["category"] == "general"

    @pytest.mark.asyncio
    async def test_filter_by_pronunciation_category(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/youtube/channels?category=pronunciation")
        assert response.status_code == 200
        data = response.json()
        for ch in data["channels"]:
            assert ch["category"] == "pronunciation"

    @pytest.mark.asyncio
    async def test_filter_unknown_category_returns_empty(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/youtube/channels?category=nonexistent")
        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 0
        assert data["channels"] == []

    @pytest.mark.asyncio
    async def test_channel_has_required_fields(self, no_db_client: AsyncClient):
        response = await no_db_client.get("/api/v1/youtube/channels")
        assert response.status_code == 200
        channels = response.json()["channels"]
        for ch in channels:
            assert "id" in ch
            assert "name" in ch
            assert "description" in ch
            assert "level" in ch
            assert "thumbnail" in ch
            assert "category" in ch


# ============================================================================
# Route Tests — GET /youtube/search
# ============================================================================

class TestSearchVideos:
    """Tests for GET /youtube/search endpoint."""

    @pytest.mark.asyncio
    async def test_requires_query_param(self, no_db_client: AsyncClient):
        """Should return 422 if 'q' param is missing."""
        response = await no_db_client.get("/api/v1/youtube/search")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_query_min_length_violation(self, no_db_client: AsyncClient):
        """Single char should fail min_length=2 validation."""
        response = await no_db_client.get("/api/v1/youtube/search?q=a")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_max_results_out_of_range(self, no_db_client: AsyncClient):
        """max_results > 25 should fail validation."""
        response = await no_db_client.get("/api/v1/youtube/search?q=english&max_results=30")
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_503_when_no_api_key_configured(self, no_db_client: AsyncClient):
        """Should return 503 when YOUTUBE_API_KEY is not set."""
        with patch("app.routes.youtube.settings") as mock_settings:
            mock_settings.YOUTUBE_API_KEY = None
            response = await no_db_client.get("/api/v1/youtube/search?q=english")
        assert response.status_code == 503

    @pytest.mark.asyncio
    async def test_returns_cached_response(self, no_db_client: AsyncClient):
        """Should return data from cache service."""
        mock_result = MagicMock()
        mock_result.data = {
            "videos": [
                {
                    "video_id": "test123",
                    "title": "Learn English",
                    "description": "English lesson",
                    "channel_title": "BBC",
                    "channel_id": "ch123",
                    "published_at": "2024-01-01T00:00:00Z",
                    "thumbnail_url": "https://example.com/thumb.jpg",
                    "thumbnail_medium": "https://example.com/thumb_m.jpg",
                }
            ],
            "next_page_token": None,
            "prev_page_token": None,
            "total_results": 1,
        }
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get("/api/v1/youtube/search?q=english")

        assert response.status_code == 200
        data = response.json()
        assert "data" in data
        assert "source" in data
        assert data["source"] == "redis"
        assert data["is_stale"] is False

    @pytest.mark.asyncio
    async def test_429_when_quota_exhausted(self, no_db_client: AsyncClient):
        """Should return 429 when quota is exhausted."""
        from app.services.api_cache_service import QuotaExhaustedError

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.side_effect = QuotaExhaustedError(
                "youtube", reset_time="2024-01-02T00:00:00Z"
            )
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get("/api/v1/youtube/search?q=english")

        assert response.status_code == 429

    @pytest.mark.asyncio
    async def test_search_with_channel_id_filter(self, no_db_client: AsyncClient):
        """search with channelId should pass it to cache key."""
        mock_result = MagicMock()
        mock_result.data = {"videos": [], "next_page_token": None,
                           "prev_page_token": None, "total_results": 0}
        mock_result.source = "api"
        mock_result.is_stale = False

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get(
                "/api/v1/youtube/search?q=grammar&channel_id=UCHaHD477h-FeBbrgBrwTDpA"
            )

        assert response.status_code == 200
        # Verify cache key included channel_id
        call_args = mock_cache_instance.get_or_fetch.call_args
        cache_key = call_args.kwargs.get("cache_key") or call_args.args[0]
        assert "UCHaHD477h-FeBbrgBrwTDpA" in cache_key


# ============================================================================
# Route Tests — GET /youtube/captions/{video_id}
# ============================================================================

class TestGetCaptions:
    """Tests for GET /youtube/captions/{video_id} endpoint."""

    @pytest.mark.asyncio
    async def test_returns_caption_segments(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = [
            {"start_ms": 0, "end_ms": 2000, "text": "Hello everyone"},
            {"start_ms": 2000, "end_ms": 4000, "text": "Welcome to this lesson"},
        ]
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get("/api/v1/youtube/captions/dQw4w9WgXcQ")

        assert response.status_code == 200
        data = response.json()
        assert data["video_id"] == "dQw4w9WgXcQ"
        assert data["language"] == "en"
        assert len(data["segments"]) == 2
        assert data["segments"][0]["text"] == "Hello everyone"

    @pytest.mark.asyncio
    async def test_default_language_is_en(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = []
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get("/api/v1/youtube/captions/videoabc")

        assert response.status_code == 200
        assert response.json()["language"] == "en"

    @pytest.mark.asyncio
    async def test_custom_language_parameter(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = []
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get("/api/v1/youtube/captions/videoabc?lang=vi")

        assert response.status_code == 200
        assert response.json()["language"] == "vi"

    @pytest.mark.asyncio
    async def test_permanent_cache_key_includes_video_and_lang(self, no_db_client: AsyncClient):
        """Verify cache key format is youtube:captions:{video_id}:{lang}"""
        mock_result = MagicMock()
        mock_result.data = []
        mock_result.source = "db"
        mock_result.is_stale = False

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache_instance

            await no_db_client.get("/api/v1/youtube/captions/myVideoId123?lang=en")

        call_kwargs = mock_cache_instance.get_or_fetch.call_args.kwargs
        assert call_kwargs["cache_key"] == "youtube:captions:myVideoId123:en"


# ============================================================================
# Route Tests — GET /youtube/channels/{channel_id}/videos
# ============================================================================

class TestGetChannelVideos:
    """Tests for GET /youtube/channels/{channel_id}/videos endpoint."""

    @pytest.mark.asyncio
    async def test_503_when_no_api_key(self, no_db_client: AsyncClient):
        with patch("app.routes.youtube.settings") as mock_settings:
            mock_settings.YOUTUBE_API_KEY = None
            response = await no_db_client.get(
                "/api/v1/youtube/channels/UCHaHD477h-FeBbrgBrwTDpA/videos"
            )
        assert response.status_code == 503

    @pytest.mark.asyncio
    async def test_returns_videos_for_channel(self, no_db_client: AsyncClient):
        mock_result = MagicMock()
        mock_result.data = {
            "videos": [
                {
                    "video_id": "v1",
                    "title": "Lesson 1",
                    "description": "",
                    "channel_title": "BBC",
                    "channel_id": "UCHaHD477h-FeBbrgBrwTDpA",
                    "published_at": "2024-01-01T00:00:00Z",
                    "thumbnail_url": "",
                    "thumbnail_medium": "",
                }
            ],
            "next_page_token": None,
            "prev_page_token": None,
            "total_results": 1,
        }
        mock_result.source = "redis"
        mock_result.is_stale = False

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get(
                "/api/v1/youtube/channels/UCHaHD477h-FeBbrgBrwTDpA/videos"
            )

        assert response.status_code == 200
        data = response.json()
        assert data["channel_id"] == "UCHaHD477h-FeBbrgBrwTDpA"
        assert "data" in data
        assert "source" in data

    @pytest.mark.asyncio
    async def test_max_results_validation(self, no_db_client: AsyncClient):
        """max_results > 50 should fail validation."""
        with patch("app.routes.youtube.settings") as mock_settings:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            response = await no_db_client.get(
                "/api/v1/youtube/channels/UCtest/videos?max_results=100"
            )
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_429_on_quota_near_limit(self, no_db_client: AsyncClient):
        from app.services.api_cache_service import QuotaNearLimitError

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("app.routes.youtube.APICacheService") as MockCache:
            mock_settings.YOUTUBE_API_KEY = "fake_key"
            mock_cache_instance = AsyncMock()
            mock_cache_instance.get_or_fetch.side_effect = QuotaNearLimitError(
                "youtube", level="CRITICAL", message="Near limit"
            )
            MockCache.return_value = mock_cache_instance

            response = await no_db_client.get(
                "/api/v1/youtube/channels/UCtest/videos"
            )

        assert response.status_code == 429


# ============================================================================
# Integration Tests — YouTube Search Internal Function
# ============================================================================

class TestYoutubeSearchInternal:
    """Tests for _youtube_search internal function with mocked HTTP."""

    @pytest.mark.asyncio
    async def test_transforms_api_response_to_normalized_format(self):
        from app.routes.youtube import _youtube_search

        mock_response_data = {
            "items": [
                {
                    "id": {"videoId": "vid001"},
                    "snippet": {
                        "title": "English Grammar Lesson",
                        "description": "Learn grammar",
                        "channelTitle": "BBC Learning English",
                        "channelId": "UCHaHD477h",
                        "publishedAt": "2024-01-15T10:00:00Z",
                        "thumbnails": {
                            "high": {"url": "https://example.com/high.jpg"},
                            "medium": {"url": "https://example.com/medium.jpg"},
                        },
                    },
                }
            ],
            "nextPageToken": "page2token",
            "pageInfo": {"totalResults": 100},
        }

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.YOUTUBE_API_KEY = "test_key"

            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.json.return_value = mock_response_data
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _youtube_search(q="grammar", max_results=10)

        assert len(result["videos"]) == 1
        video = result["videos"][0]
        assert video["video_id"] == "vid001"
        assert video["title"] == "English Grammar Lesson"
        assert video["channel_title"] == "BBC Learning English"
        assert video["thumbnail_url"] == "https://example.com/high.jpg"
        assert result["next_page_token"] == "page2token"
        assert result["total_results"] == 100

    @pytest.mark.asyncio
    async def test_empty_items_returns_empty_videos(self):
        from app.routes.youtube import _youtube_search

        with patch("app.routes.youtube.settings") as mock_settings, \
             patch("httpx.AsyncClient") as MockClient:
            mock_settings.YOUTUBE_API_KEY = "test_key"

            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.json.return_value = {"items": [], "pageInfo": {"totalResults": 0}}
            mock_resp.raise_for_status = MagicMock()

            mock_http = AsyncMock()
            mock_http.get.return_value = mock_resp
            MockClient.return_value.__aenter__.return_value = mock_http

            result = await _youtube_search(q="nonexistent1234567890")

        assert result["videos"] == []
        assert result["total_results"] == 0
