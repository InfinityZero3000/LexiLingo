import asyncio
import threading
from unittest.mock import AsyncMock

import pytest

from api.services import kg_service_v3, model_gateway
from api.services import orchestrator as orchestrator_module
from api.services.trace_cag import graph
from api.core.config import settings


@pytest.mark.asyncio
async def test_blocking_kg_initialization_does_not_block_event_loop(monkeypatch):
    started = threading.Event()
    release = threading.Event()
    kg = object()

    def blocking_get_kg_service():
        started.set()
        release.wait(timeout=1)
        return kg

    monkeypatch.setattr(kg_service_v3, "get_kg_service", blocking_get_kg_service)
    monkeypatch.setattr(model_gateway, "get_gateway", AsyncMock(return_value=object()))
    monkeypatch.setattr(graph, "get_trace_cag", AsyncMock(return_value=object()))
    orchestrator = orchestrator_module.AIOrchestrator()
    task = asyncio.create_task(orchestrator.initialize())

    try:
        for _ in range(50):
            if started.is_set():
                break
            await asyncio.sleep(0.002)
        assert started.is_set()

        heartbeat = asyncio.Event()
        asyncio.get_running_loop().call_soon(heartbeat.set)
        await asyncio.wait_for(heartbeat.wait(), timeout=0.05)
        assert not task.done()
    finally:
        release.set()

    await asyncio.wait_for(task, timeout=0.5)
    assert orchestrator._kg is kg
    assert orchestrator._initialized is True


@pytest.mark.asyncio
async def test_concurrent_get_orchestrator_initializes_single_instance_once(monkeypatch):
    calls = 0
    entered = asyncio.Event()
    release = asyncio.Event()

    async def initialize(self):
        nonlocal calls
        calls += 1
        entered.set()
        await release.wait()
        self._initialized = True

    monkeypatch.setattr(orchestrator_module.AIOrchestrator, "initialize", initialize)
    monkeypatch.setattr(orchestrator_module, "_orchestrator", None)
    monkeypatch.setattr(orchestrator_module, "_orchestrator_lock", asyncio.Lock())

    tasks = [
        asyncio.create_task(orchestrator_module.get_orchestrator()) for _ in range(20)
    ]
    await asyncio.wait_for(entered.wait(), timeout=0.1)
    await asyncio.sleep(0)
    assert calls == 1
    release.set()

    instances = await asyncio.gather(*tasks)

    assert calls == 1
    assert len({id(instance) for instance in instances}) == 1
    assert instances[0] is orchestrator_module._orchestrator


def test_failed_kg_initialization_releases_process_lock(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "KUZU_DB_PATH", str(tmp_path / "failed-kuzu"))
    monkeypatch.setattr(
        kg_service_v3,
        "get_kg_service",
        lambda: (_ for _ in ()).throw(RuntimeError("open failed")),
    )
    orchestrator_module._release_kg_process_lock()

    with pytest.raises(RuntimeError, match="open failed"):
        orchestrator_module._get_kg_service_with_process_lock()

    assert orchestrator_module._kuzu_process_lock_file is None


@pytest.mark.asyncio
async def test_cancelled_first_waiter_does_not_duplicate_initialization(monkeypatch):
    calls = 0
    entered = asyncio.Event()
    release = asyncio.Event()

    async def initialize(self):
        nonlocal calls
        calls += 1
        entered.set()
        await release.wait()
        self._initialized = True

    monkeypatch.setattr(orchestrator_module.AIOrchestrator, "initialize", initialize)
    monkeypatch.setattr(orchestrator_module, "_orchestrator", None)
    monkeypatch.setattr(orchestrator_module, "_orchestrator_init_task", None)
    monkeypatch.setattr(orchestrator_module, "_orchestrator_lock", asyncio.Lock())

    first = asyncio.create_task(orchestrator_module.get_orchestrator())
    await entered.wait()
    first.cancel()
    with pytest.raises(asyncio.CancelledError):
        await first
    second = asyncio.create_task(orchestrator_module.get_orchestrator())
    await asyncio.sleep(0)
    assert calls == 1
    release.set()

    instance = await second
    assert instance is orchestrator_module._orchestrator
    assert calls == 1
