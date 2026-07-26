import hashlib
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from api.core.auth import AuthenticatedUser, get_current_user
from api.routes import voice
from api.services.stt import voice_ticket


@pytest.mark.asyncio
async def test_issue_stores_sha256_key_not_raw_ticket(monkeypatch):
    redis = AsyncMock()
    redis.set.return_value = True
    monkeypatch.setattr(voice_ticket, "get_redis", AsyncMock(return_value=redis))
    monkeypatch.setattr(voice_ticket.secrets, "token_urlsafe", lambda _size: "raw-ticket")

    ticket, expires_in = await voice_ticket.issue_voice_ticket("u1")

    expected_key = "voice:ticket:" + hashlib.sha256(b"raw-ticket").hexdigest()
    assert (ticket, expires_in) == ("raw-ticket", 30)
    redis.set.assert_awaited_once_with(expected_key, "u1", ex=30, nx=True)
    assert "raw-ticket" not in expected_key


@pytest.mark.asyncio
async def test_redis_ticket_getdel_is_single_use(monkeypatch):
    redis = AsyncMock()
    redis.getdel.side_effect = ["u1", None]
    monkeypatch.setattr(voice_ticket, "get_redis", AsyncMock(return_value=redis))

    assert await voice_ticket.consume_voice_ticket("ticket") == "u1"
    assert await voice_ticket.consume_voice_ticket("ticket") is None
    assert redis.getdel.await_count == 2
    assert redis.getdel.await_args_list[0] == redis.getdel.await_args_list[1]


@pytest.mark.asyncio
async def test_expired_development_fallback_is_rejected(monkeypatch):
    monkeypatch.setattr(voice_ticket.settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(
        voice_ticket, "get_redis", AsyncMock(side_effect=RuntimeError("redis down"))
    )
    monkeypatch.setattr(voice_ticket.time, "monotonic", lambda: 100.0)
    voice_ticket._local.clear()
    voice_ticket._local[voice_ticket._key("expired")] = ("u1", 99.0)

    assert await voice_ticket.consume_voice_ticket("expired") is None
    assert voice_ticket._key("expired") not in voice_ticket._local


@pytest.mark.asyncio
async def test_production_redis_failure_fails_closed(monkeypatch):
    monkeypatch.setattr(voice_ticket.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(
        voice_ticket, "get_redis", AsyncMock(side_effect=RuntimeError("redis down"))
    )

    with pytest.raises(RuntimeError, match="redis down"):
        await voice_ticket.issue_voice_ticket("u1")
    assert await voice_ticket.consume_voice_ticket("ticket") is None


@pytest.mark.asyncio
async def test_ticket_route_requires_auth_and_voice_router_mounts_stream(monkeypatch):
    app = FastAPI()
    app.include_router(voice.router, prefix="/api/v1/voice")
    assert any(route.path == "/stream" for route in voice.router.routes)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        assert (await client.post("/api/v1/voice/ticket")).status_code == 401

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        user_id="u1", token_type="access", claims={}
    )
    monkeypatch.setattr(voice.settings, "VOICE_DUPLEX_ENABLED", True)
    quota = AsyncMock(return_value=None)
    monkeypatch.setattr(voice, "enforce_user_quota", quota)
    monkeypatch.setattr(voice, "issue_voice_ticket", AsyncMock(return_value=("ticket", 30)))
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/api/v1/voice/ticket")
    assert response.json() == {"ticket": "ticket", "expires_in": 30}
    quota.assert_awaited_once_with(
        "u1", "voice.ticket", token_cost=1, fail_closed=True
    )


@pytest.mark.asyncio
async def test_ticket_route_is_hidden_when_duplex_disabled(monkeypatch):
    app = FastAPI()
    app.include_router(voice.router, prefix="/api/v1/voice")
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        user_id="u1", token_type="access", claims={}
    )
    monkeypatch.setattr(voice.settings, "VOICE_DUPLEX_ENABLED", False)
    issue = AsyncMock()
    monkeypatch.setattr(voice, "issue_voice_ticket", issue)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/api/v1/voice/ticket")

    assert response.status_code == 404
    issue.assert_not_awaited()


@pytest.mark.asyncio
async def test_voice_readiness_fails_closed_and_reports_no_secrets(monkeypatch):
    monkeypatch.setattr(voice.settings, "VOICE_DUPLEX_ENABLED", True)
    monkeypatch.setattr(voice, "get_redis", AsyncMock(side_effect=RuntimeError("secret host")))

    response = await voice.ready()

    assert response.status_code == 503
    assert b"secret host" not in response.body


@pytest.mark.asyncio
async def test_voice_readiness_checks_all_enabled_dependencies(monkeypatch):
    redis = AsyncMock()
    registry = type("Registry", (), {"status": "ready"})()
    tts = type("TTS", (), {"sample_rate": 22050})()
    monkeypatch.setattr(voice.settings, "VOICE_DUPLEX_ENABLED", True)
    monkeypatch.setattr(voice, "get_redis", AsyncMock(return_value=redis))
    monkeypatch.setattr(voice, "get_stt_registry", lambda: registry)
    monkeypatch.setattr(voice, "get_configured_key_count", lambda: 2)
    monkeypatch.setattr(voice, "get_tts_service", lambda: tts)
    collection = MagicMock()
    collection.index_information = AsyncMock(
        return_value={"lexi_messages_session_id_uq": {"unique": True}}
    )
    database = MagicMock()
    database.__getitem__.return_value = collection
    monkeypatch.setattr(voice, "mongodb_manager", MagicMock(db=database))

    response = await voice.ready()

    assert response.status_code == 200
    assert response.body == b'{"ready":true,"status":"ready"}'
    redis.ping.assert_awaited_once_with()
