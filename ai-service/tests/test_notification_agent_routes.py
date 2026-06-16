"""Tests for api/routes/notification_agent.py — notification content generation endpoint."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import FastAPI
from httpx import AsyncClient, ASGITransport

from api.routes.notification_agent import router, GenerateContentResponse


def _make_app() -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    return app


_VALID_REQUEST = {
    "title": "Daily streak reminder",
    "body": "Keep your streak alive — just 5 minutes today!",
    "notification_type": "campaign",
    "audience_profile": {"level": "A2", "streak_days": 7},
}


@pytest.mark.asyncio
async def test_generate_content_missing_header_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "secret-admin-key")
    app = _make_app()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/api/notification-agent/generate-content", json=_VALID_REQUEST)

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_generate_content_wrong_key_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "correct-secret-key")
    app = _make_app()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/notification-agent/generate-content",
            json=_VALID_REQUEST,
            headers={"X-Admin-Api-Key": "wrong-key"},
        )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_generate_content_no_env_key_configured_returns_500(monkeypatch):
    monkeypatch.delenv("AI_ADMIN_API_KEY", raising=False)
    app = _make_app()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/notification-agent/generate-content",
            json=_VALID_REQUEST,
            headers={"X-Admin-Api-Key": "any-key"},
        )

    assert response.status_code == 500
    assert "AI_ADMIN_API_KEY" in response.json()["detail"]


@pytest.mark.asyncio
async def test_generate_content_pipeline_success_returns_response(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "valid-admin-key")
    app = _make_app()

    pipeline_result = {
        "title": "Don't break your streak!",
        "body": "You're 7 days in — keep going!",
        "score": 0.92,
        "retries": 1,
        "generation_skipped": False,
        "variants": [
            {"title": "Don't break your streak!", "body": "You're 7 days in — keep going!", "rationale": "Direct appeal"},
            {"title": "One more day!", "body": "5 minutes keeps your streak alive.", "rationale": "Low friction"},
        ],
    }
    mock_pipeline = MagicMock()
    mock_pipeline.run = AsyncMock(return_value=pipeline_result)

    with patch("api.routes.notification_agent.get_notification_agent_pipeline", return_value=mock_pipeline):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/notification-agent/generate-content",
                json=_VALID_REQUEST,
                headers={"X-Admin-Api-Key": "valid-admin-key"},
            )

    assert response.status_code == 200
    data = response.json()
    assert data["best_variant"]["title"] == "Don't break your streak!"
    assert data["best_variant"]["body"] == "You're 7 days in — keep going!"
    assert len(data["all_variants"]) == 2
    assert data["score"] == 0.92
    assert data["retries"] == 1
    assert data["generation_skipped"] is False


@pytest.mark.asyncio
async def test_generate_content_pipeline_raises_exception_returns_500(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "valid-admin-key")
    app = _make_app()

    mock_pipeline = MagicMock()
    mock_pipeline.run = AsyncMock(side_effect=RuntimeError("LangGraph node failed"))

    with patch("api.routes.notification_agent.get_notification_agent_pipeline", return_value=mock_pipeline):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/notification-agent/generate-content",
                json=_VALID_REQUEST,
                headers={"X-Admin-Api-Key": "valid-admin-key"},
            )

    assert response.status_code == 500
    assert "LangGraph node failed" in response.json()["detail"]


@pytest.mark.asyncio
async def test_generate_content_generation_skipped_propagated(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "valid-admin-key")
    app = _make_app()

    pipeline_result = {
        "title": "Daily streak reminder",
        "body": "Keep your streak alive — just 5 minutes today!",
        "score": 0.0,
        "retries": 0,
        "generation_skipped": True,
        "variants": [],
    }
    mock_pipeline = MagicMock()
    mock_pipeline.run = AsyncMock(return_value=pipeline_result)

    with patch("api.routes.notification_agent.get_notification_agent_pipeline", return_value=mock_pipeline):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/notification-agent/generate-content",
                json=_VALID_REQUEST,
                headers={"X-Admin-Api-Key": "valid-admin-key"},
            )

    assert response.status_code == 200
    data = response.json()
    assert data["generation_skipped"] is True
    assert data["best_variant"]["title"] == "Daily streak reminder"
