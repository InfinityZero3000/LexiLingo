import asyncio
import time

import pytest

from api.services.stt.config import STTConfig
from api.services.stt.errors import STTProtocolError
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.schemas import StartMessage
from api.services.stt.session_manager import SessionManager
from tests.stt.fakes import FakePrimary, FakeVerifier


class BlockingPrimary(FakePrimary):
    async def create_session(self, language):
        await asyncio.Event().wait()


@pytest.mark.asyncio
async def test_manager_resume_returns_same_session(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path))
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    session = await manager.create(StartMessage(session_id="s1"))
    manager.mark_disconnected("s1")
    assert manager.resume("s1", -1) is session
    await manager.shutdown()


@pytest.mark.asyncio
async def test_manager_rejects_session_over_capacity(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), max_active_sessions=1)
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    await manager.create(StartMessage(session_id="s1"))
    with pytest.raises(STTProtocolError):
        await manager.create(StartMessage(session_id="s2"))
    await manager.shutdown()


@pytest.mark.asyncio
async def test_resume_window_expires(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), resume_window_seconds=1)
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    session = await manager.create(StartMessage(session_id="s1"))
    session.disconnected_at = time.monotonic() - 2
    with pytest.raises(STTProtocolError):
        manager.resume("s1", -1)
    await manager.shutdown()


@pytest.mark.asyncio
async def test_manager_enforces_per_user_capacity(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        max_active_sessions=4,
        max_sessions_per_user=1,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    await manager.create(StartMessage(session_id="s1", user_id="u1"))

    with pytest.raises(STTProtocolError):
        await manager.create(StartMessage(session_id="s2", user_id="u1"))

    await manager.create(StartMessage(session_id="s3", user_id="u2"))
    await manager.shutdown()


@pytest.mark.asyncio
async def test_resume_rejects_sequence_ahead_of_server(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path))
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    await manager.create(StartMessage(session_id="s1", user_id="u1"))

    with pytest.raises(STTProtocolError):
        manager.resume("s1", 1, "u1")

    await manager.shutdown()


@pytest.mark.asyncio
async def test_concurrent_session_creation_cannot_bypass_capacity(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), max_active_sessions=1)
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)

    results = await asyncio.gather(
        manager.create(StartMessage(session_id="s1", user_id="u1")),
        manager.create(StartMessage(session_id="s2", user_id="u2")),
        return_exceptions=True,
    )

    assert sum(not isinstance(result, Exception) for result in results) == 1
    assert sum(isinstance(result, STTProtocolError) for result in results) == 1
    await manager.shutdown()


def test_connection_admission_is_bounded_per_user(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), max_connections_per_user=1)
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    manager = SessionManager(config, registry)

    assert manager.acquire_connection("u1")
    assert not manager.acquire_connection("u1")
    assert manager.acquire_connection("u2")
    manager.release_connection("u1")
    assert manager.acquire_connection("u1")


@pytest.mark.asyncio
async def test_stalled_session_start_times_out_and_releases_reservation(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        max_active_sessions=1,
        session_start_timeout_seconds=0.01,
    )
    registry = STTModelRegistry(
        config, primary=BlockingPrimary(), verifier=FakeVerifier()
    )
    registry.status = "ready"
    manager = SessionManager(config, registry)

    with pytest.raises(asyncio.TimeoutError):
        await manager.create(StartMessage(session_id="blocked", user_id="u1"))

    assert not manager.sessions
    assert not manager._pending_sessions


@pytest.mark.asyncio
async def test_cancelled_session_start_releases_reservation(tmp_path):
    config = STTConfig(
        temp_dir=str(tmp_path),
        max_active_sessions=1,
        session_start_timeout_seconds=10,
    )
    registry = STTModelRegistry(
        config, primary=BlockingPrimary(), verifier=FakeVerifier()
    )
    registry.status = "ready"
    manager = SessionManager(config, registry)
    task = asyncio.create_task(
        manager.create(StartMessage(session_id="cancelled", user_id="u1"))
    )
    await asyncio.sleep(0)

    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task

    assert not manager.sessions
    assert not manager._pending_sessions


@pytest.mark.asyncio
async def test_idle_session_is_closed_by_manager(tmp_path):
    config = STTConfig(temp_dir=str(tmp_path), session_idle_timeout_seconds=0)
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)

    session = await manager.create(StartMessage(session_id="idle"))
    session.last_activity = time.monotonic() - 1.0

    now = time.monotonic()
    for sid, s in list(manager.sessions.items()):
        if now - s.last_activity > manager.config.session_idle_timeout_seconds:
            await manager.close(sid, "idle_timeout")

    assert "idle" not in manager.sessions
    await manager.shutdown()
