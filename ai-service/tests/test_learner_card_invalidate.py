"""The invalidation endpoint must be locked down and must actually drop the key."""

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from api.routes import learner_card_cache


@pytest.fixture
def client_app(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key-0123456789")
    app = FastAPI()
    app.include_router(learner_card_cache.router)
    return app


@pytest.mark.asyncio
async def test_invalidate_drops_the_cached_card(client_app, monkeypatch):
    dropped: list[str] = []

    async def fake_invalidate(user_id: str) -> None:
        dropped.append(user_id)

    monkeypatch.setattr(learner_card_cache, "invalidate", fake_invalidate)

    transport = ASGITransport(app=client_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/api/v1/internal/learner-card/invalidate",
            headers={"X-Admin-Api-Key": "test-admin-key-0123456789"},
            json={"user_id": "user-1"},
        )

    assert response.status_code == 200
    assert dropped == ["user-1"]


@pytest.mark.asyncio
async def test_invalidate_refuses_a_wrong_or_missing_key(client_app, monkeypatch):
    async def fail_if_called(user_id: str) -> None:
        raise AssertionError("cache must not be touched without a valid key")

    monkeypatch.setattr(learner_card_cache, "invalidate", fail_if_called)

    transport = ASGITransport(app=client_app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        wrong = await client.post(
            "/api/v1/internal/learner-card/invalidate",
            headers={"X-Admin-Api-Key": "nope"},
            json={"user_id": "user-1"},
        )
        missing = await client.post(
            "/api/v1/internal/learner-card/invalidate",
            json={"user_id": "user-1"},
        )

    assert wrong.status_code == 403
    assert missing.status_code == 403
