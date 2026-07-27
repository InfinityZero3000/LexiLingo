"""Tests for api/routes/ollama_router.py — Ollama health, chat, analyze, models."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import FastAPI
from httpx import AsyncClient, ASGITransport

from api.routes.ollama_router import router


def _make_app() -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    return app


def _mock_ollama_service(
    health: bool = True,
    models: list | None = None,
    generate_response: str = "Good job!",
    analyze_result: dict | None = None,
) -> MagicMock:
    svc = MagicMock()
    svc.health_check = AsyncMock(return_value=health)
    svc.list_models = AsyncMock(return_value=models or ["lexilingo-qwen3-1.7b"])
    svc.generate = AsyncMock(return_value=generate_response)
    svc.analyze_text = AsyncMock(return_value=analyze_result or {"score": 0.9, "feedback": "Great grammar."})
    return svc


def _admin_headers(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    return {"X-Admin-Key": "test-admin-key"}


@pytest.mark.asyncio
async def test_ollama_health_real_settings_field_returns_disabled_response(monkeypatch):
    monkeypatch.setattr("api.routes.ollama_router.settings.USE_OLLAMA", False)
    app = _make_app()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/ollama/health")

    assert response.status_code == 503
    assert "disabled" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_ollama_health_use_ollama_false_returns_503():
    app = _make_app()

    with patch("api.routes.ollama_router.settings") as mock_settings:
        mock_settings.USE_OLLAMA = False
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/ollama/health")

    assert response.status_code == 503
    assert "disabled" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_ollama_health_use_ollama_true_healthy_returns_200(monkeypatch):
    app = _make_app()
    svc = _mock_ollama_service(health=True, models=["lexilingo-qwen3-1.7b", "other-model"])

    with (
        patch("api.routes.ollama_router.settings") as mock_settings,
        patch("api.routes.ollama_router.get_ollama_service", return_value=svc),
    ):
        mock_settings.USE_OLLAMA = True
        mock_settings.OLLAMA_BASE_URL = "http://localhost:11434"
        mock_settings.OLLAMA_MODEL = "lexilingo-qwen3-1.7b"
        headers = _admin_headers(monkeypatch)

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/ollama/health", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "lexilingo-qwen3-1.7b" in data["available_models"]
    assert data["model_loaded"] is True


@pytest.mark.asyncio
async def test_ollama_health_use_ollama_true_unhealthy_returns_error(monkeypatch):
    app = _make_app()
    svc = _mock_ollama_service(health=False)

    with (
        patch("api.routes.ollama_router.settings") as mock_settings,
        patch("api.routes.ollama_router.get_ollama_service", return_value=svc),
    ):
        mock_settings.USE_OLLAMA = True
        headers = _admin_headers(monkeypatch)
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/ollama/health", headers=headers)

    assert response.status_code == 503
    assert "not responding" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_ollama_chat_use_ollama_false_returns_503():
    app = _make_app()

    with patch("api.routes.ollama_router.settings") as mock_settings:
        mock_settings.USE_OLLAMA = False
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post("/ollama/chat", json={"message": "Hello!"})

    assert response.status_code == 503


@pytest.mark.asyncio
async def test_ollama_chat_success_returns_response_and_model(monkeypatch):
    app = _make_app()
    svc = _mock_ollama_service(generate_response="Great question about grammar!")

    with (
        patch("api.routes.ollama_router.settings") as mock_settings,
        patch("api.routes.ollama_router.get_ollama_service", return_value=svc),
    ):
        mock_settings.USE_OLLAMA = True
        mock_settings.OLLAMA_MODEL = "lexilingo-qwen3-1.7b"
        headers = _admin_headers(monkeypatch)

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/ollama/chat",
                json={"message": "What is the past tense of 'go'?", "temperature": 0.5},
                headers=headers,
            )

    assert response.status_code == 200
    data = response.json()
    assert data["response"] == "Great question about grammar!"
    assert data["model"] == "lexilingo-qwen3-1.7b"
    assert data["message"] == "What is the past tense of 'go'?"


@pytest.mark.asyncio
async def test_ollama_analyze_success_returns_task_result_model(monkeypatch):
    app = _make_app()
    analysis = {"score": 0.85, "errors": [], "feedback": "Well done."}
    svc = _mock_ollama_service(analyze_result=analysis)

    with (
        patch("api.routes.ollama_router.settings") as mock_settings,
        patch("api.routes.ollama_router.get_ollama_service", return_value=svc),
    ):
        mock_settings.USE_OLLAMA = True
        mock_settings.OLLAMA_MODEL = "lexilingo-qwen3-1.7b"
        headers = _admin_headers(monkeypatch)

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/ollama/analyze",
                json={"text": "She go to the store.", "task": "grammar", "language": "en"},
                headers=headers,
            )

    assert response.status_code == 200
    data = response.json()
    assert data["task"] == "grammar"
    assert data["result"] == analysis
    assert data["model"] == "lexilingo-qwen3-1.7b"
    assert data["text"] == "She go to the store."


@pytest.mark.asyncio
async def test_ollama_models_success_returns_models_list(monkeypatch):
    app = _make_app()
    model_list = ["lexilingo-qwen3-1.7b", "llama3:8b"]
    svc = _mock_ollama_service(models=model_list)

    with (
        patch("api.routes.ollama_router.settings") as mock_settings,
        patch("api.routes.ollama_router.get_ollama_service", return_value=svc),
    ):
        mock_settings.USE_OLLAMA = True
        mock_settings.OLLAMA_MODEL = "lexilingo-qwen3-1.7b"
        headers = _admin_headers(monkeypatch)

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/ollama/models", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert data["models"] == model_list
    assert data["count"] == 2
    assert data["current"] == "lexilingo-qwen3-1.7b"
