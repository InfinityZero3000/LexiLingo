import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport
import urllib.parse

# Fixture: no-DB async client
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

class TestPodcastProxyImage:
    """Tests for GET /podcasts/proxy/image endpoint."""

    @pytest.mark.asyncio
    async def test_proxy_image_success(self, no_db_client: AsyncClient):
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"content-type": "image/png"}
        mock_response.aclose = AsyncMock()
        async def chunks():
            yield b"fake_image_bytes"
        mock_response.aiter_bytes = chunks

        target_url = "https://example.com/artwork.png"
        with patch(
            "app.routes.podcasts._stream_public_url",
            AsyncMock(return_value=mock_response),
        ):
            response = await no_db_client.get(f"{BASE}/proxy/image?url={target_url}")

        assert response.status_code == 200
        assert response.content == b"fake_image_bytes"
        assert response.headers.get("content-type") == "image/png"
        assert response.headers.get("cache-control") == "public, max-age=86400"

    @pytest.mark.asyncio
    async def test_proxy_image_not_image_type(self, no_db_client: AsyncClient):
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"content-type": "text/html"}
        mock_response.aclose = AsyncMock()

        target_url = "https://example.com/artwork.html"
        with patch(
            "app.routes.podcasts._stream_public_url",
            AsyncMock(return_value=mock_response),
        ):
            response = await no_db_client.get(f"{BASE}/proxy/image?url={target_url}")

        assert response.status_code == 400
        assert "did not return an image content type" in response.json()["error"]["message"]

    @pytest.mark.asyncio
    async def test_proxy_image_non_200_response(self, no_db_client: AsyncClient):
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_response.aclose = AsyncMock()

        target_url = "https://example.com/artwork.png"
        with patch(
            "app.routes.podcasts._stream_public_url",
            AsyncMock(return_value=mock_response),
        ):
            response = await no_db_client.get(f"{BASE}/proxy/image?url={target_url}")

        assert response.status_code == 404
        assert "Failed to fetch image: HTTP 404" in response.json()["error"]["message"]

    @pytest.mark.asyncio
    async def test_proxy_image_invalid_scheme(self, no_db_client: AsyncClient):
        target_url = "ftp://example.com/artwork.png"
        response = await no_db_client.get(f"{BASE}/proxy/image?url={target_url}")
        assert response.status_code == 400
        assert "Only public HTTP/HTTPS URLs are allowed" in response.json()["error"]["message"]

    @pytest.mark.asyncio
    async def test_proxy_image_ssrf_private_ip(self, no_db_client: AsyncClient):
        # Localhost/private domain check
        for private_url in [
            "https://localhost/image.png",
            "http://127.0.0.1/image.png",
            "http://192.168.1.1/image.png",
            "http://10.0.0.1/image.png"
        ]:
            response = await no_db_client.get(f"{BASE}/proxy/image?url={private_url}")
            assert response.status_code == 400
            assert "Only public HTTP/HTTPS URLs are allowed" in response.json()["error"]["message"]

class TestPodcastRouteProxiedUrls:
    """Tests that curated, search, and episode routes return proxied URLs."""

    @pytest.mark.asyncio
    async def test_curated_rewrites_artwork_url(self, no_db_client: AsyncClient):
        response = await no_db_client.get(f"{BASE}/curated")
        assert response.status_code == 200
        data = response.json()
        assert "podcasts" in data
        for p in data["podcasts"]:
            assert "artwork_url" in p
            assert p["artwork_url"].startswith("http://test/api/v1/podcasts/proxy/image?url=")

    @pytest.mark.asyncio
    async def test_search_rewrites_artwork_url(self, no_db_client: AsyncClient):
        # We need to mock search cache return values
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
            mock_settings.API_V1_PREFIX = "/api/v1"
            mock_settings.PODCASTINDEX_KEY = "fake_key"
            mock_settings.PODCASTINDEX_SECRET = "fake_secret"
            mock_cache = AsyncMock()
            mock_cache.get_or_fetch.return_value = mock_result
            MockCache.return_value = mock_cache

            response = await no_db_client.get(f"{BASE}/search?q=english")

        assert response.status_code == 200
        data = response.json()
        assert "podcasts" in data
        assert len(data["podcasts"]) == 1
        podcast = data["podcasts"][0]
        assert podcast["artwork_url"].startswith("http://test/api/v1/podcasts/proxy/image?url=")
        expected_part = urllib.parse.quote("https://example.com/img.jpg")
        assert expected_part in podcast["artwork_url"]

    @pytest.mark.asyncio
    async def test_episodes_rewrites_image_url(self, no_db_client: AsyncClient):
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
                    "image_url": "https://example.com/ep_cover.jpg",
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
        assert len(data["episodes"]) == 1
        episode = data["episodes"][0]
        assert episode["image_url"].startswith("http://test/api/v1/podcasts/proxy/image?url=")
        expected_part = urllib.parse.quote("https://example.com/ep_cover.jpg")
        assert expected_part in episode["image_url"]
