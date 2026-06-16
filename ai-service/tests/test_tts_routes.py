"""Tests for api/routes/tts.py — speech synthesis endpoint."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import FastAPI, HTTPException
from httpx import AsyncClient, ASGITransport

from api.routes.tts import router
from api.core.auth import AuthenticatedUser
from api.core.quota_guard import QuotaDecision


def _make_app() -> FastAPI:
    app = FastAPI()
    app.include_router(router, prefix="/tts")
    return app


def _quota_decision(allowed: bool = True) -> QuotaDecision:
    return QuotaDecision(
        allowed=allowed,
        rpm_used=1,
        rpd_used=1,
        rpm_limit=30,
        rpd_limit=500,
        tpm_used=64,
        tpd_used=64,
        tpm_limit=12000,
        tpd_limit=200000,
        backend_available=True,
    )


def _authed_user() -> AuthenticatedUser:
    return AuthenticatedUser(
        user_id="test-user-123",
        token_type="access",
        claims={"sub": "test-user-123", "type": "access"},
    )


@pytest.mark.asyncio
async def test_synthesize_returns_local_audio_when_found():
    app = _make_app()
    user = _authed_user()
    quota = _quota_decision()

    from api.core.auth import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user

    with (
        patch("api.routes.tts.enforce_user_quota", new=AsyncMock(return_value=quota)),
        patch("api.routes.tts.run_in_threadpool", new=AsyncMock(return_value=(b"local-audio-bytes", "audio/mpeg"))),
        patch("api.routes.tts.emit_ai_audit_event", new=AsyncMock()),
    ):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post("/tts/synthesize", json={"text": "hello"})

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/mpeg"
    assert response.content == b"local-audio-bytes"


@pytest.mark.asyncio
async def test_synthesize_piper_succeeds_when_no_local_audio():
    app = _make_app()
    user = _authed_user()
    quota = _quota_decision()

    from api.core.auth import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user

    piper_wav_bytes = b"RIFF....WAVEfmt "

    mock_tts_service = MagicMock()
    mock_tts_service.synthesize = MagicMock(return_value=piper_wav_bytes)

    run_call_count = 0

    async def fake_run_in_threadpool(func, *args, **kwargs):
        nonlocal run_call_count
        run_call_count += 1
        if run_call_count == 1:
            return None
        return func(*args, **kwargs)

    with (
        patch("api.routes.tts.enforce_user_quota", new=AsyncMock(return_value=quota)),
        patch("api.routes.tts.run_in_threadpool", side_effect=fake_run_in_threadpool),
        patch("api.routes.tts.get_tts_service", return_value=mock_tts_service),
        patch("api.routes.tts.emit_ai_audit_event", new=AsyncMock()),
    ):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post("/tts/synthesize", json={"text": "hello world"})

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert response.content == piper_wav_bytes


@pytest.mark.asyncio
async def test_synthesize_gtts_fallback_when_piper_fails():
    """When get_tts_service() raises (Piper unavailable), the route falls back to
    gTTS. run_in_threadpool is called twice: once for find_local_audio (→ None),
    once for the gTTS generate_gtts closure (→ mp3 bytes)."""
    app = _make_app()
    user = _authed_user()
    quota = _quota_decision()

    from api.core.auth import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user

    gtts_mp3_bytes = b"ID3\x03\x00gtts-audio"

    run_call_count = 0

    async def fake_run_in_threadpool(func, *args, **kwargs):
        nonlocal run_call_count
        run_call_count += 1
        if run_call_count == 1:
            return None
        return gtts_mp3_bytes

    import sys
    mock_gtts_module = MagicMock()
    mock_gtts_instance = MagicMock()
    mock_gtts_instance.write_to_fp = MagicMock()
    mock_gtts_module.gTTS = MagicMock(return_value=mock_gtts_instance)

    with (
        patch("api.routes.tts.enforce_user_quota", new=AsyncMock(return_value=quota)),
        patch("api.routes.tts.run_in_threadpool", side_effect=fake_run_in_threadpool),
        patch("api.routes.tts.get_tts_service", side_effect=RuntimeError("Piper not available")),
        patch("api.routes.tts.emit_ai_audit_event", new=AsyncMock()),
        patch.dict(sys.modules, {"gtts": mock_gtts_module}),
    ):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post("/tts/synthesize", json={"text": "hello"})

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/mpeg"
    assert response.content == gtts_mp3_bytes


@pytest.mark.asyncio
async def test_synthesize_quota_exceeded_returns_429():
    app = _make_app()
    user = _authed_user()

    from api.core.auth import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user

    async def raise_quota(*args, **kwargs):
        raise HTTPException(status_code=429, detail={"message": "AI request quota exceeded"})

    with patch("api.routes.tts.enforce_user_quota", side_effect=raise_quota):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post("/tts/synthesize", json={"text": "hello"})

    assert response.status_code == 429


@pytest.mark.asyncio
async def test_synthesize_all_synthesis_fails_returns_500():
    app = _make_app()
    user = _authed_user()
    quota = _quota_decision()

    from api.core.auth import get_current_user
    app.dependency_overrides[get_current_user] = lambda: user

    run_call_count = 0

    async def fake_run_in_threadpool(func, *args, **kwargs):
        nonlocal run_call_count
        run_call_count += 1
        if run_call_count == 1:
            return None
        raise RuntimeError("All TTS backends failed")

    with (
        patch("api.routes.tts.enforce_user_quota", new=AsyncMock(return_value=quota)),
        patch("api.routes.tts.run_in_threadpool", side_effect=fake_run_in_threadpool),
        patch("api.routes.tts.get_tts_service", side_effect=RuntimeError("Piper unavailable")),
        patch("api.routes.tts.emit_ai_audit_event", new=AsyncMock()),
    ):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post("/tts/synthesize", json={"text": "hello"})

    assert response.status_code == 500
