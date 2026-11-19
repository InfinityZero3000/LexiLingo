"""Server-side caches for the cover/text proxies and the per-user recommendations."""

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.core import proxy_cache
from app.core.safe_http import MAX_PROXIED_IMAGE_BYTES
from app.routes import books, recommendations
from app.services.recommendation_client import RecommendationClient

GOOD_URL = "https://www.gutenberg.org/cache/epub/1/pg1.cover.medium.jpg"


class FakeStore:
    def __init__(self) -> None:
        self.data: dict = {}

    async def get(self, key):
        return self.data.get(key)

    async def set(self, key, value, ttl=60):
        self.data[key] = value


@pytest.fixture
def store(monkeypatch):
    fake = FakeStore()
    monkeypatch.setattr(proxy_cache, "get_cached", fake.get)
    monkeypatch.setattr(proxy_cache, "set_cached", fake.set)
    return fake


def _upstream(content_type="image/jpeg", body=b"img", status=200):
    resp = MagicMock()
    resp.status_code = status
    resp.content = body
    resp.headers = {"content-type": content_type}
    return resp


async def _get(path, **params):
    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        return await c.get(path, params=params)


async def test_second_cover_request_is_served_without_upstream(store):
    fetch = AsyncMock(return_value=_upstream(body=b"cover-bytes"))
    with patch.object(books, "_get_with_mirror", new=fetch):
        first = await _get("/api/v1/books/proxy/image", url=GOOD_URL)
        second = await _get("/api/v1/books/proxy/image", url=GOOD_URL)
    assert first.status_code == second.status_code == 200
    assert second.content == b"cover-bytes"
    assert second.headers["content-type"] == "image/jpeg"
    assert second.headers["x-content-type-options"] == "nosniff"
    assert fetch.await_count == 1


@pytest.mark.parametrize(
    "upstream",
    [
        _upstream(status=404),
        _upstream(status=500),
        _upstream(content_type="text/html"),
        _upstream(content_type="image/svg+xml"),
        _upstream(body=b"0" * (MAX_PROXIED_IMAGE_BYTES + 1)),
    ],
)
async def test_failed_or_invalid_upstream_is_not_cached(store, upstream):
    with patch.object(books, "_get_with_mirror", new=AsyncMock(return_value=upstream)):
        response = await _get("/api/v1/books/proxy/image", url=GOOD_URL)
    assert response.status_code != 200
    assert store.data == {}


async def test_validation_runs_before_the_cache(store):
    bad = "https://evil.example.com/a.jpg"
    store.data[proxy_cache.proxy_cache_key("img", bad)] = {"m": "image/jpeg", "b": "aW1n"}
    fetch = AsyncMock()
    with patch.object(books, "_get_with_mirror", new=fetch):
        response = await _get("/api/v1/books/proxy/image", url=bad)
    assert response.status_code == 400
    fetch.assert_not_awaited()


async def test_text_proxy_validates_then_caches(store):
    url = "https://www.gutenberg.org/cache/epub/1/pg1.txt"
    fetch = AsyncMock(return_value=_upstream("text/plain; charset=utf-8", b"hello"))
    with patch.object(books, "_get_with_mirror", new=fetch):
        await _get("/api/v1/books/proxy/text", url=url)
        second = await _get("/api/v1/books/proxy/text", url=url)
        denied = await _get("/api/v1/books/proxy/text", url="https://evil.example.com/x.txt")
    assert second.content == b"hello"
    assert fetch.await_count == 1
    assert denied.status_code == 400


async def test_corrupt_cache_entry_is_a_miss(store):
    store.data[proxy_cache.proxy_cache_key("img", GOOD_URL)] = {"m": "image/jpeg", "b": "!!notb64"}
    fetch = AsyncMock(return_value=_upstream(body=b"fresh"))
    with patch.object(books, "_get_with_mirror", new=fetch):
        response = await _get("/api/v1/books/proxy/image", url=GOOD_URL)
    assert response.content == b"fresh"


async def test_non_image_media_in_cache_is_never_served(store):
    store.data[proxy_cache.proxy_cache_key("img", GOOD_URL)] = {"m": "text/html", "b": "aW1n"}
    fetch = AsyncMock(return_value=_upstream(body=b"fresh"))
    with patch.object(books, "_get_with_mirror", new=fetch):
        response = await _get("/api/v1/books/proxy/image", url=GOOD_URL)
    assert response.content == b"fresh"


# ── recommendations ──────────────────────────────────────────────


@pytest.fixture
def rec_app(store, monkeypatch):
    from app.core.database import get_db
    from app.core.dependencies import get_current_user
    from app.main import app

    user = MagicMock()
    user.id = uuid.uuid4()
    app.dependency_overrides[get_current_user] = lambda: user
    app.dependency_overrides[get_db] = lambda: MagicMock()
    monkeypatch.setattr(recommendations, "get_cached", store.get)
    monkeypatch.setattr(recommendations, "set_cached", store.set)
    epochs = {"state": 1, "interaction": 1}
    monkeypatch.setattr(
        recommendations, "get_state_epoch", AsyncMock(side_effect=lambda *_: epochs["state"])
    )
    monkeypatch.setattr(
        recommendations,
        "get_interaction_epoch",
        AsyncMock(side_effect=lambda *_: epochs["interaction"]),
    )
    build = {
        "profile": AsyncMock(return_value={}),
        "candidates": AsyncMock(return_value=[]),
        "mastery": AsyncMock(side_effect=lambda db, uid, profile, cands: profile),
    }
    monkeypatch.setattr(recommendations, "build_profile", build["profile"])
    monkeypatch.setattr(recommendations, "build_candidates", build["candidates"])
    monkeypatch.setattr(recommendations, "attach_mastery", build["mastery"])
    yield app, epochs, build
    app.dependency_overrides.pop(get_current_user, None)
    app.dependency_overrides.pop(get_db, None)


def _ranked():
    return {
        "recommendations": [{"item_id": "c1", "item_type": "course", "title": "T", "score": 1.0}],
        "metadata": {"latency_ms": 5},
    }


async def _rec(app, **params):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        return await c.get("/api/v1/recommendations", params=params)


async def test_recommendations_second_call_skips_build_and_ranker(rec_app):
    app, _, build = rec_app
    with patch.object(
        RecommendationClient, "rank", autospec=True, return_value=_ranked()
    ) as rank:
        first = await _rec(app)
        second = await _rec(app)
    assert first.status_code == second.status_code == 200
    assert second.json()["data"]["cache_hit"] is True
    assert second.json()["data"]["items"] == first.json()["data"]["items"]
    assert rank.await_count == 1
    assert build["profile"].await_count == 1


@pytest.mark.parametrize("which", ["state", "interaction"])
async def test_epoch_bump_is_a_miss(rec_app, which):
    app, epochs, _ = rec_app
    with patch.object(
        RecommendationClient, "rank", autospec=True, return_value=_ranked()
    ) as rank:
        await _rec(app)
        epochs[which] += 1
        await _rec(app)
    assert rank.await_count == 2


async def test_surface_and_limit_are_part_of_the_key(rec_app):
    app, _, _ = rec_app
    with patch.object(
        RecommendationClient, "rank", autospec=True, return_value=_ranked()
    ) as rank:
        await _rec(app, surface="home", limit=10)
        await _rec(app, surface="practice", limit=10)
        await _rec(app, surface="home", limit=5)
    assert rank.await_count == 3


async def test_degraded_result_is_not_cached(rec_app, store):
    app, _, _ = rec_app
    with patch.object(
        RecommendationClient, "rank", autospec=True, return_value=None
    ) as rank:
        first = await _rec(app)
        await _rec(app)
    assert first.json()["data"]["degraded"] is True
    assert rank.await_count == 2
    assert store.data == {}
