"""Tests for AI service startup behavior."""

from __future__ import annotations

import importlib
from pathlib import Path
import re
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


def _pin_learner_state_off(ai_main, monkeypatch: pytest.MonkeyPatch) -> None:
    """Pin LEARNER_STATE_MODE so the test does not depend on a local `.env`.

    `start_learner_observation_forwarder` reaches straight for
    `mongodb_manager.db`, which raises unless a real client is connected — so
    with any mode but "off" this test failed for whoever had learner state
    enabled locally, and passed for everyone else. See
    test_lifespan_starts_the_learner_observation_forwarder for that path.
    """
    monkeypatch.setattr(ai_main.settings, "LEARNER_STATE_MODE", "off")


def _prepare_lifespan(
    monkeypatch: pytest.MonkeyPatch,
    *,
    redis_fails: bool = False,
    learner_state_mode: str = "off",
):
    """Stub everything `lifespan` reaches for, and hand back what to assert on.

    Shared so a second startup path does not mean a second copy of thirty lines
    of mocks that then drift apart.
    """
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
    import api.services.orchestrator as orchestrator_module

    timeouts = []
    real_wait_for = ai_main.asyncio.wait_for

    async def wait_for(awaitable, timeout):
        timeouts.append(timeout)
        return await real_wait_for(awaitable, timeout)

    monkeypatch.setattr(ai_main.asyncio, "wait_for", wait_for)
    monkeypatch.setattr(
        orchestrator_module,
        "get_orchestrator",
        AsyncMock(return_value=MagicMock()),
    )
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
    monkeypatch.setattr(
        ai_main,
        "get_redis",
        AsyncMock(side_effect=RuntimeError("redis down"))
        if redis_fails
        else AsyncMock(return_value=MagicMock()),
    )
    monkeypatch.setattr(ai_main, "build_groq_key_pool", MagicMock())
    monkeypatch.setattr(ai_main, "USE_GATEWAY", False)
    monkeypatch.setattr(
        ai_main.settings, "LEARNER_STATE_MODE", learner_state_mode
    )

    http_client = MagicMock()
    http_client.aclose = AsyncMock()
    monkeypatch.setattr(ai_main.httpx, "AsyncClient", MagicMock(return_value=http_client))

    return ai_main, http_client, timeouts, warmup


@pytest.mark.asyncio
async def test_lifespan_continues_when_redis_unavailable(monkeypatch: pytest.MonkeyPatch) -> None:
    ai_main, http_client, timeouts, warmup = _prepare_lifespan(
        monkeypatch, redis_fails=True
    )


    async with ai_main.lifespan(FastAPI()):
        assert ai_main._groq_pool is None

    ai_main.mongodb_manager.connect.assert_awaited_once()
    ai_main.mongodb_manager.disconnect.assert_awaited_once()
    http_client.aclose.assert_awaited_once()
    warmup.assert_called_once_with()
    assert timeouts == [45.0, 20.0]


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


# ---------------------------------------------------------------------------
# Learner-state forwarder startup
#
# `lifespan` starts the observation forwarder whenever LEARNER_STATE_MODE is not
# "off". That branch had no coverage at all: the one lifespan test pinned the
# mode by accident through a local `.env`, so whether it ran depended on the
# machine. It matters because the forwarder reaches straight for
# `mongodb_manager.db` during startup — on a box where Mongo is not up yet, that
# raises and takes the whole service down with it.
# ---------------------------------------------------------------------------


def _stub_forwarder(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    """Replace the forwarder so startup does not need a live Mongo client."""
    spool = types.ModuleType("api.services.learner_observation_spool")
    spool.start_learner_observation_forwarder = MagicMock()
    monkeypatch.setitem(sys.modules, "api.services.learner_observation_spool", spool)
    return spool.start_learner_observation_forwarder


@pytest.mark.asyncio
@pytest.mark.parametrize("mode", ["shadow", "read", "primary"])
async def test_lifespan_starts_the_forwarder_for_every_enabled_mode(
    monkeypatch: pytest.MonkeyPatch, mode: str
) -> None:
    start = _stub_forwarder(monkeypatch)
    ai_main, _, _, _ = _prepare_lifespan(monkeypatch, learner_state_mode=mode)

    async with ai_main.lifespan(FastAPI()):
        pass

    start.assert_called_once()


@pytest.mark.asyncio
async def test_lifespan_does_not_start_the_forwarder_when_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    start = _stub_forwarder(monkeypatch)
    ai_main, _, _, _ = _prepare_lifespan(monkeypatch, learner_state_mode="off")

    async with ai_main.lifespan(FastAPI()):
        pass

    start.assert_not_called()


@pytest.mark.asyncio
async def test_a_failing_forwarder_does_not_stop_startup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Chat still has to work when the spool cannot start.

    The forwarder only ships observations to backend-service; losing it costs
    skill evidence, not conversation. Taking the whole AI service down for it
    would turn a degraded feature into an outage.
    """
    start = _stub_forwarder(monkeypatch)
    start.side_effect = RuntimeError("Database not connected. Call connect() first.")
    ai_main, http_client, _, _ = _prepare_lifespan(
        monkeypatch, learner_state_mode="shadow"
    )

    async with ai_main.lifespan(FastAPI()):
        pass

    http_client.aclose.assert_awaited_once()


# ---------------------------------------------------------------------------
# Startup may degrade a feature, never the process
#
# Mongo is the one hard requirement: `lifespan` re-raises if it cannot connect,
# because nothing here works without it. Everything else is one feature among
# many, and losing the process costs chat, translate, STT and TRACE-CAG all at
# once — so an optional subsystem that cannot start must log and let boot finish.
# ---------------------------------------------------------------------------


def _lifespan_feature_blocks() -> dict[str, str]:
    """Each `if <FLAG>:` block inside lifespan, up to the `yield`."""
    source = (Path(__file__).parents[1] / "api" / "main.py").read_text()
    body = source[source.index("async def lifespan") : source.index("\n    yield")]
    return {
        match.group(1): match.group(2)
        for match in re.finditer(
            r"^    if (settings\.[A-Z_]+|[A-Z_]+)[^\n]*:\n(.*?)(?=^    [a-zA-Z_@]|\Z)",
            body,
            re.S | re.M,
        )
    }


def test_every_optional_subsystem_catches_its_own_failure():
    """Adding a fifth flag-gated subsystem without a try/except fails here.

    `start_learner_observation_forwarder` and `voice_readiness` were both
    unguarded: either could stop the service booting over a feature that is not
    even enabled in production.
    """
    blocks = _lifespan_feature_blocks()

    assert blocks, "no flag-gated blocks found — has lifespan been restructured?"
    unguarded = [flag for flag, block in blocks.items() if "try:" not in block]
    assert unguarded == [], f"unguarded optional subsystems: {unguarded}"


def test_mongo_remains_the_one_fatal_dependency():
    """The counterpart: this must NOT be softened into a warning."""
    source = (Path(__file__).parents[1] / "api" / "main.py").read_text()
    connect_block = source[
        source.index("await mongodb_manager.connect()") : source.index(
            "await mongodb_manager.connect()"
        )
        + 400
    ]

    assert "raise" in connect_block
