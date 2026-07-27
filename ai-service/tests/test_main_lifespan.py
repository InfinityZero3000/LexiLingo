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
    stt_runtime.get_stt_config = MagicMock()
    stt_runtime.get_stt_sessions = MagicMock()
    stt_runtime.get_stt_registry = MagicMock()
    monkeypatch.setitem(sys.modules, "api.services.stt.runtime", stt_runtime)

    ai_main = importlib.import_module("api.main")
    import api.services.tts_service as tts_service

    timeouts = []
    real_wait_for = ai_main.asyncio.wait_for

    async def wait_for(awaitable, timeout):
        timeouts.append(timeout)
        return await real_wait_for(awaitable, timeout)

    monkeypatch.setattr(ai_main.asyncio, "wait_for", wait_for)
    warmup = MagicMock(side_effect=RuntimeError("piper unavailable"))
    monkeypatch.setattr(
        tts_service,
        "get_tts_service",
        MagicMock(return_value=MagicMock(warmup=warmup)),
    )

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
    warmup.assert_called_once_with()
    assert timeouts == [20.0]


@pytest.mark.asyncio
@pytest.mark.parametrize(("kg_error", "expected_status"), [(None, 200), (RuntimeError("bad KG"), 503)])
async def test_health_reflects_kg_readiness(monkeypatch, kg_error, expected_status):
    _install_sentry_stub(monkeypatch)
    ai_main = importlib.import_module("api.main")
    import api.services.orchestrator as orchestrator_module

    kg = MagicMock()
    kg.assert_runtime_namespace = AsyncMock()
    if kg_error:
        kg.assert_runtime_namespace.side_effect = kg_error
    orchestrator = MagicMock(_kg=kg)
    orchestrator.is_healthy.return_value = not kg_error
    monkeypatch.setattr(
        orchestrator_module,
        "get_orchestrator",
        AsyncMock(return_value=orchestrator),
    )

    response = await ai_main.health_check()

    assert getattr(response, "status_code", 200) == expected_status
    if not kg_error:
        kg.assert_runtime_namespace.assert_awaited_once()
