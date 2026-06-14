"""Application-scoped STT runtime objects."""

from __future__ import annotations

from typing import Optional

from api.services.stt.config import STTConfig
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.session_manager import SessionManager
from api.services.stt.trace_cag_adapter import TraceCAGDispatcher

_config: Optional[STTConfig] = None
_registry: Optional[STTModelRegistry] = None
_sessions: Optional[SessionManager] = None
_trace_cag_dispatcher: Optional[TraceCAGDispatcher] = None


async def start_stt_runtime() -> None:
    global _config, _registry, _sessions, _trace_cag_dispatcher
    _config = STTConfig.from_env()
    _registry = STTModelRegistry(_config)
    await _registry.start()
    _trace_cag_dispatcher = TraceCAGDispatcher(
        processing_timeout_seconds=max(
            1.0, _config.downstream_response_timeout_seconds - 5
        )
    )
    await _trace_cag_dispatcher.start()
    _sessions = SessionManager(
        _config, _registry, final_sink=_trace_cag_dispatcher
    )
    await _sessions.start()


async def stop_stt_runtime() -> None:
    global _registry, _sessions, _trace_cag_dispatcher
    if _sessions:
        await _sessions.shutdown()
    if _trace_cag_dispatcher:
        await _trace_cag_dispatcher.close()
    if _registry:
        await _registry.close()
    _sessions = None
    _registry = None
    _trace_cag_dispatcher = None


def get_stt_config() -> STTConfig:
    if _config is None:
        raise RuntimeError("STT runtime is not initialized")
    return _config


def get_stt_registry() -> STTModelRegistry:
    if _registry is None:
        raise RuntimeError("STT runtime is not initialized")
    return _registry


def get_stt_sessions() -> SessionManager:
    if _sessions is None:
        raise RuntimeError("STT runtime is not initialized")
    return _sessions
