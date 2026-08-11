"""Create, resume, expire, and close in-process voice sessions."""

from __future__ import annotations

import asyncio
import time
from contextlib import suppress

from api.services.stt.config import STTConfig
from api.services.stt.errors import STTErrorCode, STTProtocolError
from api.services.stt.metrics import STTMetrics
from api.services.stt.schemas import StartMessage
from api.services.stt.temp_audio_writer import cleanup_stale_audio
from api.services.stt.voice_session import VoiceSession


class SessionManager:
    def __init__(self, config: STTConfig, registry, final_sink=None):
        self.config = config
        self.registry = registry
        self.final_sink = final_sink
        self.metrics = STTMetrics()
        self.sessions: dict[str, VoiceSession] = {}
        self._cleanup_task = None
        self._create_lock = asyncio.Lock()
        self._connection_counts: dict[str, int] = {}
        self._pending_sessions: dict[str, str | None] = {}

    async def start(self) -> None:
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())

    async def create(self, message: StartMessage) -> VoiceSession:
        async with self._create_lock:
            if (
                len(self.sessions) + len(self._pending_sessions)
                >= self.config.max_active_sessions
            ):
                raise STTProtocolError(
                    STTErrorCode.SERVER_BUSY, "STT session capacity reached"
                )
            user_sessions = sum(
                1
                for session in self.sessions.values()
                if not session.closed and session.start.user_id == message.user_id
            ) + sum(
                1
                for pending_user_id in self._pending_sessions.values()
                if pending_user_id == message.user_id
            )
            if user_sessions >= self.config.max_sessions_per_user:
                raise STTProtocolError(
                    STTErrorCode.SERVER_BUSY, "Per-user STT session capacity reached"
                )
            existing = self.sessions.get(message.session_id)
            if (
                (existing and not existing.closed)
                or message.session_id in self._pending_sessions
            ):
                raise STTProtocolError(
                    STTErrorCode.INVALID_START, "Session already exists"
                )
            self._pending_sessions[message.session_id] = message.user_id

        session = VoiceSession(
            message,
            self.config,
            self.registry,
            self.metrics,
            None if message.duplex else self.final_sink,
        )
        try:
            await asyncio.wait_for(
                session.start_worker(),
                timeout=self.config.session_start_timeout_seconds,
            )
        except BaseException:
            async with self._create_lock:
                self._pending_sessions.pop(message.session_id, None)
            await asyncio.shield(session.stop("start_failed"))
            raise

        async with self._create_lock:
            self._pending_sessions.pop(message.session_id, None)
            self.sessions[message.session_id] = session
            self.metrics.increment("stt_sessions_started")
        return session

    def acquire_connection(self, user_id: str) -> bool:
        current = self._connection_counts.get(user_id, 0)
        if current >= self.config.max_connections_per_user:
            return False
        self._connection_counts[user_id] = current + 1
        return True

    def release_connection(self, user_id: str) -> None:
        current = self._connection_counts.get(user_id, 0)
        if current <= 1:
            self._connection_counts.pop(user_id, None)
        else:
            self._connection_counts[user_id] = current - 1

    def resume(
        self, session_id: str, last_seq: int, user_id: str | None = None
    ) -> VoiceSession:
        session = self.sessions.get(session_id)
        if not session or session.closed:
            raise STTProtocolError(STTErrorCode.SESSION_EXPIRED, "Session expired")
        if user_id and session.start.user_id != user_id:
            raise STTProtocolError(STTErrorCode.SESSION_NOT_FOUND, "Session not found")
        if last_seq > session.last_ack_seq:
            raise STTProtocolError(
                STTErrorCode.INVALID_START,
                "Resume sequence is ahead of the server checkpoint",
            )
        if session.disconnected_at is not None:
            if (
                time.monotonic() - session.disconnected_at
                > self.config.resume_window_seconds
            ):
                raise STTProtocolError(
                    STTErrorCode.SESSION_EXPIRED, "Resume window expired"
                )
        session.disconnected_at = None
        self.metrics.increment("stt_websocket_reconnect_count")
        return session

    def mark_disconnected(self, session_id: str) -> None:
        session = self.sessions.get(session_id)
        if session and not session.closed:
            session.disconnected_at = time.monotonic()

    async def close(self, session_id: str, reason: str = "client_stop") -> None:
        session = self.sessions.pop(session_id, None)
        if session:
            await session.stop(reason)

    async def shutdown(self) -> None:
        if self._cleanup_task:
            self._cleanup_task.cancel()
            with suppress(asyncio.CancelledError):
                await self._cleanup_task
        await asyncio.gather(
            *(self.close(session_id, "shutdown") for session_id in list(self.sessions)),
            return_exceptions=True,
        )

    async def _cleanup_loop(self) -> None:
        cleanup_ticks = 0
        try:
            while True:
                await asyncio.sleep(1)
                cleanup_ticks += 1
                now = time.monotonic()
                for session_id, session in list(self.sessions.items()):
                    age = now - session.last_activity
                    hard = now - session.started_at
                    if age > self.config.session_idle_timeout_seconds:
                        await self.close(session_id, "idle_timeout")
                    elif hard > self.config.session_hard_limit_minutes * 60:
                        await self.close(session_id, "hard_limit")
                    elif (
                        session.disconnected_at
                        and now - session.disconnected_at
                        > self.config.resume_window_seconds
                    ):
                        await self.close(session_id, "disconnect_timeout")
                if cleanup_ticks >= 60:
                    cleanup_stale_audio(
                        self.config.temp_dir,
                        self.config.temp_file_ttl_minutes * 60,
                    )
                    cleanup_ticks = 0
        except asyncio.CancelledError:
            return
