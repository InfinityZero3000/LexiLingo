import struct
import sys
from unittest.mock import MagicMock

from fastapi import FastAPI
from fastapi.testclient import TestClient
from jose import jwt

# api.routes eagerly imports analytics routes that require optional KuzuDB.
sys.modules.setdefault("kuzu", MagicMock())
from api.routes import stt as stt_route
from api.services.stt.audio_ingest import HEADER
from api.services.stt.config import STTConfig
from api.services.stt.model_registry import STTModelRegistry
from api.services.stt.schemas import FinalTranscriptEvent, StartMessage
from api.services.stt.session_manager import SessionManager
from api.services.stt.voice_session import VoiceSession
from tests.stt.fakes import FakePrimary, FakeVerifier


def _access_token(secret="test-secret"):
    return jwt.encode(
        {
            "sub": "u1",
            "type": "access",
            "iss": "lexilingo-backend",
            "aud": "lexilingo-services",
        },
        secret,
        algorithm="HS256",
    )


def test_websocket_requires_auth(monkeypatch):
    app = FastAPI()
    app.include_router(stt_route.router, prefix="/api/v1/stt")
    with TestClient(app) as client:
        with client.websocket_connect("/api/v1/stt/stream") as socket:
            event = socket.receive_json()
            assert event["type"] == "stt.error"


def test_websocket_start_ack_and_stop(monkeypatch, tmp_path):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    config = STTConfig(
        temp_dir=str(tmp_path),
        min_speech_ms=20,
        min_silence_ms=20,
        verify_enabled=False,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    monkeypatch.setattr(stt_route, "get_stt_config", lambda: config)
    monkeypatch.setattr(stt_route, "get_stt_sessions", lambda: manager)
    quota_calls = []

    async def allow_quota(*args, **kwargs):
        quota_calls.append((args, kwargs))
        return None

    monkeypatch.setattr(stt_route, "enforce_user_quota", allow_quota)
    token = _access_token()
    app = FastAPI()
    app.include_router(stt_route.router, prefix="/api/v1/stt")

    with TestClient(app) as client:
        with client.websocket_connect(
            "/api/v1/stt/stream",
            headers={"Authorization": f"Bearer {token}"},
        ) as socket:
            socket.send_json(
                {
                    "type": "start",
                    "session_id": "s1",
                    "user_id": "u1",
                    "sample_rate": 16000,
                    "channels": 1,
                    "format": "pcm16",
                }
            )
            assert socket.receive_json()["type"] == "session_started"
            assert quota_calls[0][0][:2] == ("u1", "stt.stream")
            pcm = struct.pack("<h", 5000) * 320
            socket.send_bytes(HEADER.pack(1, 0, 0, 0) + pcm)
            messages = [socket.receive_json(), socket.receive_json()]
            assert {message["type"] for message in messages} == {"ack", "stt.partial"}
            socket.send_json({"type": "stop", "session_id": "s1"})
            while socket.receive_json()["type"] != "session_closed":
                pass


def test_websocket_rejects_token_without_access_type(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    token = jwt.encode(
        {
            "sub": "u1",
            "iss": "lexilingo-backend",
            "aud": "lexilingo-services",
        },
        "test-secret",
        algorithm="HS256",
    )
    app = FastAPI()
    app.include_router(stt_route.router, prefix="/api/v1/stt")

    with TestClient(app) as client:
        with client.websocket_connect(
            "/api/v1/stt/stream",
            headers={"Authorization": f"Bearer {token}"},
        ) as socket:
            assert socket.receive_json()["code"] == "INVALID_START"


def test_websocket_start_message_times_out(monkeypatch, tmp_path):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    config = STTConfig(
        temp_dir=str(tmp_path),
        first_message_timeout_seconds=0.01,
    )
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    monkeypatch.setattr(stt_route, "get_stt_config", lambda: config)
    monkeypatch.setattr(stt_route, "get_stt_sessions", lambda: manager)
    token = _access_token()
    app = FastAPI()
    app.include_router(stt_route.router, prefix="/api/v1/stt")

    with TestClient(app) as client:
        with client.websocket_connect(
            "/api/v1/stt/stream",
            headers={"Authorization": f"Bearer {token}"},
        ) as socket:
            event = socket.receive_json()
            assert event["message"] == "Start message timeout"


def test_websocket_resume_replays_final_transcripts(monkeypatch, tmp_path):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    config = STTConfig(temp_dir=str(tmp_path))
    registry = STTModelRegistry(config, primary=FakePrimary(), verifier=FakeVerifier())
    registry.status = "ready"
    manager = SessionManager(config, registry)
    session = VoiceSession(
        StartMessage(session_id="s1", user_id="u1"),
        config,
        registry,
        manager.metrics,
    )
    final = FinalTranscriptEvent(
        session_id="s1",
        utterance_id="u1",
        turn_id="t1",
        text="hello.",
        start_ms=0,
        end_ms=1000,
        confidence=0.9,
        confidence_source="test",
        source="moonshine",
        verified=False,
        uncertain=False,
        needs_confirmation=False,
    )
    session.transcripts.add_final(final)
    session.event_queue.put_nowait(final.model_dump())
    manager.sessions["s1"] = session
    monkeypatch.setattr(stt_route, "get_stt_config", lambda: config)
    monkeypatch.setattr(stt_route, "get_stt_sessions", lambda: manager)
    token = _access_token()
    app = FastAPI()
    app.include_router(stt_route.router, prefix="/api/v1/stt")

    with TestClient(app) as client:
        with client.websocket_connect(
            "/api/v1/stt/stream",
            headers={"Authorization": f"Bearer {token}"},
        ) as socket:
            socket.send_json({"type": "resume", "session_id": "s1", "last_seq": -1})
            assert socket.receive_json()["resumed"] is True
            replay = socket.receive_json()
            assert replay["type"] == "stt.final"
            assert replay["replayed"] is True
            socket.send_json({"type": "stop", "session_id": "s1"})
            assert socket.receive_json()["type"] == "session_closed"
