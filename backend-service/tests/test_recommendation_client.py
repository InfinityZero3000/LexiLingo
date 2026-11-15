"""The ranker client returns None — the caller's degraded path — on anything but a ranking."""

import httpx
import pytest

from app.services import recommendation_client as rc


def _client_with(monkeypatch, handler):
    real = httpx.AsyncClient

    def factory(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return real(*args, **kwargs)

    monkeypatch.setattr(rc.httpx, "AsyncClient", factory)
    client = rc.RecommendationClient()
    client._api_key = "key"
    client._base_url = "http://ai"
    return client


async def _rank(client):
    return await client.rank(user_id="u", surface="home", k=3, profile={}, candidates=[])


@pytest.mark.parametrize(
    "payload",
    [{"ok": True}, {"recommendations": None}, ["not", "a", "dict"]],
)
async def test_a_200_that_is_not_a_ranking_degrades(monkeypatch, payload):
    client = _client_with(monkeypatch, lambda request: httpx.Response(200, json=payload))
    assert await _rank(client) is None


async def test_a_ranking_is_passed_through(monkeypatch):
    body = {"recommendations": [{"item_id": "c1"}], "metadata": {"cache_hit": True}}
    client = _client_with(monkeypatch, lambda request: httpx.Response(200, json=body))
    assert await _rank(client) == body


async def test_a_non_200_degrades(monkeypatch):
    client = _client_with(monkeypatch, lambda request: httpx.Response(503))
    assert await _rank(client) is None
