"""Tests for api/routes/admin.py — config and topics endpoints."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
from httpx import AsyncClient, ASGITransport
from fastapi import FastAPI

from api.routes.admin import (
    router,
    verify_admin_api_key,
    get_admin_config,
    update_admin_config,
    AiConfig,
    mask_api_key,
)


def _make_app() -> FastAPI:
    app = FastAPI()
    app.include_router(router, prefix="/admin")
    return app


def _mock_db(find_one_result=None) -> MagicMock:
    db = MagicMock()
    collection = MagicMock()
    collection.find_one = AsyncMock(return_value=find_one_result)
    collection.update_one = AsyncMock(return_value=MagicMock())
    db.admin_config = collection
    return db


@pytest.mark.asyncio
async def test_get_config_no_stored_config_returns_default_with_env_key(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    monkeypatch.setenv("GEMINI_API_KEY", "AIzaTestKey1234567890xyz")

    db = _mock_db(find_one_result=None)
    app = _make_app()
    app.dependency_overrides[__import__("api.core.database", fromlist=["get_database"]).get_database] = lambda: db

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/admin/config", headers={"X-Admin-Key": "test-admin-key"})

    assert response.status_code == 200
    data = response.json()
    assert data["model_name"] == "gemini-1.5-flash"
    assert data["gemini_api_key"] is not None
    assert "***" in data["gemini_api_key"]
    assert "AIzaTestKey1234567890xyz" not in data["gemini_api_key"]


@pytest.mark.asyncio
async def test_get_config_stored_config_returns_stored_with_masked_key(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)

    stored = {
        "_id": "ai_config",
        "gemini_api_key": "AIzaStoredKey9876543210abc",
        "model_name": "gemini-1.5-pro",
        "gemini_model": "gemini-1.5-pro",
        "temperature": 0.5,
        "max_tokens": 1024,
        "top_p": 0.8,
        "top_k": 30,
        "use_mongodb": True,
        "enable_voice": False,
        "enable_grammar": True,
        "enable_topic": True,
        "chat_memory_turns": 5,
    }
    db = _mock_db(find_one_result=stored)
    app = _make_app()
    app.dependency_overrides[__import__("api.core.database", fromlist=["get_database"]).get_database] = lambda: db

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/admin/config", headers={"X-Admin-Key": "test-admin-key"})

    assert response.status_code == 200
    data = response.json()
    assert data["model_name"] == "gemini-1.5-pro"
    assert data["gemini_api_key"] == "AIza***...***abc"
    assert data["temperature"] == 0.5
    assert data["enable_voice"] is False


@pytest.mark.asyncio
async def test_put_config_valid_aiza_key_upserts_and_returns_success(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")

    db = _mock_db()
    app = _make_app()
    app.dependency_overrides[__import__("api.core.database", fromlist=["get_database"]).get_database] = lambda: db

    payload = {
        "model_name": "gemini-1.5-flash",
        "temperature": 0.7,
        "max_tokens": 2048,
        "top_p": 0.9,
        "top_k": 40,
        "gemini_api_key": "AIzaNewValidKey1234567890",
        "use_mongodb": True,
        "enable_voice": True,
        "enable_grammar": True,
        "enable_topic": True,
        "chat_memory_turns": 10,
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.put("/admin/config", json=payload, headers={"X-Admin-Key": "test-admin-key"})

    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "Configuration updated" in data["message"]
    assert "***" in data["config"]["gemini_api_key"]
    db.admin_config.update_one.assert_called_once()


@pytest.mark.asyncio
async def test_put_config_invalid_key_format_returns_400(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")

    db = _mock_db()
    app = _make_app()
    app.dependency_overrides[__import__("api.core.database", fromlist=["get_database"]).get_database] = lambda: db

    payload = {
        "model_name": "gemini-1.5-flash",
        "temperature": 0.7,
        "max_tokens": 2048,
        "top_p": 0.9,
        "top_k": 40,
        "gemini_api_key": "sk-notgemini-key-12345",
        "use_mongodb": True,
        "enable_voice": True,
        "enable_grammar": True,
        "enable_topic": True,
        "chat_memory_turns": 10,
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.put("/admin/config", json=payload, headers={"X-Admin-Key": "test-admin-key"})

    assert response.status_code == 400
    assert "AIza" in response.json()["detail"]


@pytest.mark.asyncio
async def test_get_config_missing_admin_api_key_env_returns_503(monkeypatch):
    monkeypatch.delenv("AI_ADMIN_API_KEY", raising=False)

    db = _mock_db()
    app = _make_app()
    app.dependency_overrides[__import__("api.core.database", fromlist=["get_database"]).get_database] = lambda: db

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/admin/config", headers={"X-Admin-Key": "anything"})

    assert response.status_code == 503


@pytest.mark.asyncio
async def test_get_config_wrong_api_key_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "correct-secret-key")

    db = _mock_db()
    app = _make_app()
    app.dependency_overrides[__import__("api.core.database", fromlist=["get_database"]).get_database] = lambda: db

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/admin/config", headers={"X-Admin-Key": "wrong-key"})

    assert response.status_code == 403


# ── Unit tests for pure functions ────────────────────────────────────────────


def test_mask_api_key_shows_prefix_and_suffix():
    masked = mask_api_key("AIzaTestKey1234567890xyz")
    assert masked == "AIza***...***xyz"


def test_mask_api_key_short_key_returns_none():
    assert mask_api_key("short") is None


def test_mask_api_key_none_returns_none():
    assert mask_api_key(None) is None


def test_mask_api_key_empty_returns_none():
    assert mask_api_key("") is None


# ── verify_admin_api_key unit tests ──────────────────────────────────────────


@pytest.mark.asyncio
async def test_verify_admin_api_key_correct_key_passes(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "my-secret-key")
    result = await verify_admin_api_key(api_key="my-secret-key")
    assert result == "my-secret-key"


@pytest.mark.asyncio
async def test_verify_admin_api_key_wrong_key_raises_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "correct-key")
    with pytest.raises(HTTPException) as exc:
        await verify_admin_api_key(api_key="wrong-key")
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_verify_admin_api_key_missing_env_raises_503(monkeypatch):
    monkeypatch.delenv("AI_ADMIN_API_KEY", raising=False)
    with pytest.raises(HTTPException) as exc:
        await verify_admin_api_key(api_key="any-key")
    assert exc.value.status_code == 503
