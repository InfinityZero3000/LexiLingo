"""Anonymous full-content and media search: per-IP strict limits, anonymous access kept."""

from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.core import middleware
from app.core.middleware import RateLimitMiddleware
from app.main import app

FULL_CONTENT = "/api/v1/news/full-content"
YT_SEARCH = "/api/v1/youtube/search"
POD_SEARCH = "/api/v1/podcasts/search"


@pytest.fixture
def real_limiter(monkeypatch):
    monkeypatch.setattr(RateLimitMiddleware, "_testing", False)
    monkeypatch.setattr(middleware, "_STRICT_RATE_LIMITS", dict(middleware._STRICT_RATE_LIMITS))
    with patch("app.core.redis.RedisClient.get_instance", AsyncMock(return_value=None)):
        yield


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app, client=("203.0.113.9", 1234)), base_url="http://t")


def test_strict_limits_are_registered_for_public_endpoints():
    for path in (FULL_CONTENT, YT_SEARCH, POD_SEARCH):
        assert middleware._build_strict_limits(False)[path] <= 30
        assert path in middleware._build_strict_limits(True)


@pytest.mark.asyncio
async def test_full_content_is_open_to_anonymous_callers_when_not_limited(monkeypatch):
    monkeypatch.setattr(
        "app.routes.news._scrape_full_article",
        AsyncMock(return_value={"content": "article text"}),
    )
    async with _client() as client:
        resp = await client.post(FULL_CONTENT, json={"url": "https://example.com/a"})
    assert resp.status_code == 200
    assert resp.json()["content"] == "article text"


@pytest.mark.asyncio
async def test_full_content_still_refuses_private_urls():
    async with _client() as client:
        resp = await client.post(FULL_CONTENT, json={"url": "http://127.0.0.1/admin"})
    assert resp.status_code in (400, 422)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "method,path,kwargs",
    [
        ("post", FULL_CONTENT, {"json": {"url": "http://127.0.0.1/x"}}),
        ("get", YT_SEARCH, {"params": {"q": "english"}}),
        ("get", POD_SEARCH, {"params": {"q": "english"}}),
    ],
)
async def test_anonymous_flood_from_one_ip_gets_429(real_limiter, monkeypatch, method, path, kwargs):
    middleware._STRICT_RATE_LIMITS[path] = 3
    async with _client() as client:
        codes = [(await getattr(client, method)(path, **kwargs)).status_code for _ in range(5)]
    assert 429 not in codes[:3]
    assert codes[3:] == [429, 429]


@pytest.mark.asyncio
async def test_limit_is_per_path_not_shared(real_limiter):
    middleware._STRICT_RATE_LIMITS[YT_SEARCH] = 1
    async with _client() as client:
        await client.get(YT_SEARCH, params={"q": "english"})
        blocked = await client.get(YT_SEARCH, params={"q": "english"})
        other = await client.get(POD_SEARCH, params={"q": "english"})
    assert blocked.status_code == 429
    assert other.status_code != 429
