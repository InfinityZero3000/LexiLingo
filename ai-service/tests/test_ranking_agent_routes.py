"""Tests for api/routes/ranking_agent.py — ranking agent insights endpoint."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import FastAPI
from httpx import AsyncClient, ASGITransport

from api.routes.ranking_agent import router


def _make_app() -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    return app


_LEAGUE_RESET_PAYLOAD = {
    "job_type": "league_reset",
    "artifact": {
        "week": "2026-W24",
        "total_participants": 250,
        "promotions": [{"user_id": "u1"}, {"user_id": "u2"}],
        "demotions": [{"user_id": "u3"}],
        "league_summary": {
            "Gold": {"promoted": 2, "demoted": 0},
            "Silver": {"promoted": 0, "demoted": 1},
        },
    },
}


@pytest.mark.asyncio
async def test_insights_missing_key_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "secret-key")
    app = _make_app()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/v1/internal/ranking-agent/insights",
            json=_LEAGUE_RESET_PAYLOAD,
        )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_insights_wrong_key_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "correct-key")
    app = _make_app()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/v1/internal/ranking-agent/insights",
            json=_LEAGUE_RESET_PAYLOAD,
            headers={"X-Admin-Api-Key": "wrong-key"},
        )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_insights_no_env_key_returns_503(monkeypatch):
    monkeypatch.delenv("AI_ADMIN_API_KEY", raising=False)
    app = _make_app()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/v1/internal/ranking-agent/insights",
            json=_LEAGUE_RESET_PAYLOAD,
            headers={"X-Admin-Api-Key": "any-key"},
        )

    assert response.status_code == 503
    assert "AI_ADMIN_API_KEY" in response.json()["detail"]


@pytest.mark.asyncio
async def test_insights_returns_insight_string_when_groq_responds(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "valid-admin-key")
    app = _make_app()

    insight_text = "2 promotions out of 250 participants suggests healthy but selective advancement. Consider extending the XP event window to drive more engagement."

    mock_groq_pool = MagicMock()

    with (
        patch("api.routes.ranking_agent.get_ranking_insights", new=AsyncMock(return_value=insight_text)),
        patch("api.routes.ranking_agent.get_groq_key_pool", return_value=mock_groq_pool),
    ):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/v1/internal/ranking-agent/insights",
                json=_LEAGUE_RESET_PAYLOAD,
                headers={"X-Admin-Api-Key": "valid-admin-key"},
            )

    assert response.status_code == 200
    data = response.json()
    assert data["insight"] == insight_text
    assert data["skipped"] is False


@pytest.mark.asyncio
async def test_insights_returns_skipped_true_when_groq_returns_none(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "valid-admin-key")
    app = _make_app()

    mock_groq_pool = MagicMock()

    with (
        patch("api.routes.ranking_agent.get_ranking_insights", new=AsyncMock(return_value=None)),
        patch("api.routes.ranking_agent.get_groq_key_pool", return_value=mock_groq_pool),
    ):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/v1/internal/ranking-agent/insights",
                json=_LEAGUE_RESET_PAYLOAD,
                headers={"X-Admin-Api-Key": "valid-admin-key"},
            )

    assert response.status_code == 200
    data = response.json()
    assert data["insight"] is None
    assert data["skipped"] is True
