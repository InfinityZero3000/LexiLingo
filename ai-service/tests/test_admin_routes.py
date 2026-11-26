"""Tests for api/routes/admin.py — the admin key gate and the removed config routes."""

import pytest
from fastapi import HTTPException

from api.routes.admin import router, verify_admin_api_key


def test_there_is_no_config_route_that_nothing_reads():
    # It saved Gemini settings to Mongo that no chat, voice or grammar path ever loaded.
    assert [route.path for route in router.routes if route.path.endswith("/config")] == []


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
