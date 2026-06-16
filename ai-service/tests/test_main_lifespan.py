"""Tests for AI service startup behavior."""

from __future__ import annotations

import importlib
import sys
import types
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI


def _install_sentry_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    sentry = types.ModuleType("sentry_sdk")
    sentry.init = lambda *args, **kwargs: None

    integrations = types.ModuleType("sentry_sdk.integrations")
    fastapi_integration = types.ModuleType("sentry_sdk.integrations.fastapi")
    fastapi_integration.FastApiIntegration = object

    monkeypatch.setitem(sys.modules, "sentry_sdk", sentry)
    monkeypatch.setitem(sys.modules, "sentry_sdk.integrations", integrations)
    monkeypatch.setitem(sys.modules, "sentry_sdk.integrations.fastapi", fastapi_integration)


@pytest.mark.asyncio
async def test_lifespan_continues_when_redis_unavailable(monkeypatch: pytest.MonkeyPatch) -> None:
    _install_sentry_stub(monkeypatch)

    stt_runtime = types.ModuleType("api.services.stt.runtime")
    stt_runtime.start_stt_runtime = AsyncMock()
    stt_runtime.stop_stt_runtime = AsyncMock()
    monkeypatch.setitem(sys.modules, "api.services.stt.runtime", stt_runtime)

    ai_main = importlib.import_module("api.main")

    monkeypatch.setattr(ai_main.mongodb_manager, "connect", AsyncMock())
    monkeypatch.setattr(ai_main.mongodb_manager, "disconnect", AsyncMock())
    monkeypatch.setattr(ai_main.RedisClient, "close", AsyncMock())
    monkeypatch.setattr(ai_main, "_ensure_mongo_indexes", AsyncMock())
    monkeypatch.setattr(ai_main, "get_redis", AsyncMock(side_effect=RuntimeError("redis down")))
    monkeypatch.setattr(ai_main, "build_groq_key_pool", MagicMock())
    monkeypatch.setattr(ai_main, "USE_GATEWAY", False)

    http_client = MagicMock()
    http_client.aclose = AsyncMock()
    monkeypatch.setattr(ai_main.httpx, "AsyncClient", MagicMock(return_value=http_client))

    async with ai_main.lifespan(FastAPI()):
        assert ai_main._groq_pool is None

    ai_main.mongodb_manager.connect.assert_awaited_once()
    ai_main.mongodb_manager.disconnect.assert_awaited_once()
    http_client.aclose.assert_awaited_once()
