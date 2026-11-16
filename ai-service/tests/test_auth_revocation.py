"""Revocation signals from backend-service: blacklisted tokens, inactive users, input caps."""

import logging
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import redis.asyncio as redis
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from jose import jwt
from pydantic import ValidationError

from api.core import auth_revocation
from api.core.auth import get_current_user
from api.models.schemas import MAX_CHAT_MESSAGE_CHARS, SendMessageRequest
from api.models.story_schemas import TopicChatRequest
from api.services.lexi_chat_service import LexiChatRequest

SECRET = "test-secret"


@pytest.fixture(autouse=True)
def _pinned_env(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", SECRET)
    monkeypatch.setenv("ALGORITHM", "HS256")
    monkeypatch.setenv("AUTH_REVOCATION_CHECK", "on")
    monkeypatch.setattr(auth_revocation, "_last_failure_log", 0.0)


def _token(sub: str = "user-123") -> str:
    return jwt.encode(
        {"sub": sub, "type": "access", "iss": "lexilingo-backend", "aud": "lexilingo-services"},
        SECRET,
        algorithm="HS256",
    )


def _creds(token: str) -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def _fake_redis(results):
    pipe = MagicMock(spec=redis.client.Pipeline)
    pipe.execute = AsyncMock(return_value=results) if not isinstance(results, Exception) else AsyncMock(side_effect=results)
    client = MagicMock(spec=redis.Redis)
    client.pipeline.return_value = pipe
    return client, pipe


@pytest.mark.asyncio
async def test_clean_token_is_accepted():
    client, pipe = _fake_redis([0, 0])
    with patch.object(auth_revocation, "_get_client", autospec=True, return_value=client):
        user = await get_current_user(credentials=_creds(_token()))
    assert user.user_id == "user-123"
    keys = [c.args[0] for c in pipe.exists.call_args_list]
    assert keys == [auth_revocation.blacklist_key(_token()), "user:inactive:user-123"]


@pytest.mark.asyncio
async def test_blacklisted_token_is_401():
    client, _ = _fake_redis([1, 0])
    with patch.object(auth_revocation, "_get_client", autospec=True, return_value=client):
        with pytest.raises(HTTPException) as exc:
            await get_current_user(credentials=_creds(_token()))
    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_inactive_user_is_401():
    client, _ = _fake_redis([0, 1])
    with patch.object(auth_revocation, "_get_client", autospec=True, return_value=client):
        with pytest.raises(HTTPException) as exc:
            await get_current_user(credentials=_creds(_token()))
    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_redis_error_fails_open_and_is_logged_and_counted(caplog):
    client, _ = _fake_redis(redis.ConnectionError("down"))
    telemetry = MagicMock()
    with patch.object(auth_revocation, "_get_client", autospec=True, return_value=client), \
         patch("api.services.telemetry.get_telemetry", autospec=True, return_value=telemetry), \
         caplog.at_level(logging.WARNING, logger=auth_revocation.logger.name):
        user = await get_current_user(credentials=_creds(_token()))
    assert user.user_id == "user-123"
    assert "fail open" in caplog.text
    telemetry.increment_counter.assert_called_once_with(auth_revocation.FAILURE_COUNTER)


@pytest.mark.asyncio
async def test_kill_switch_skips_redis(monkeypatch):
    monkeypatch.setenv("AUTH_REVOCATION_CHECK", "off")
    with patch.object(auth_revocation, "_get_client", autospec=True) as get_client:
        await get_current_user(credentials=_creds(_token()))
    get_client.assert_not_called()


def test_blacklist_key_matches_backend_format():
    token = "a" * 10 + "b" * 32
    assert auth_revocation.blacklist_key(token) == "blacklist:token:" + "b" * 32
    assert auth_revocation.blacklist_key("short") == "blacklist:token:short"


@pytest.mark.parametrize(
    "build",
    [
        lambda m: SendMessageRequest(session_id="s", user_id="u", message=m),
        lambda m: TopicChatRequest(user_id="u", message=m),
        lambda m: LexiChatRequest(message=m),
    ],
)
def test_overlong_message_is_rejected_and_limit_is_accepted(build):
    build("x" * MAX_CHAT_MESSAGE_CHARS)
    with pytest.raises(ValidationError) as exc:
        build("x" * (MAX_CHAT_MESSAGE_CHARS + 1))
    assert "at most 4000" in str(exc.value)


@pytest.mark.asyncio
async def test_overlong_message_over_http_is_422():
    from fastapi import FastAPI
    from httpx import ASGITransport, AsyncClient

    from api.routes import lexi_chat as lexi_route
    from api.core.auth import AuthenticatedUser

    app = FastAPI()
    app.include_router(lexi_route.router)
    app.dependency_overrides[lexi_route.get_current_user] = lambda: AuthenticatedUser(
        user_id="u", claims={}
    )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as client:
        resp = await client.post("/api/v1/lexi/chat", json={"message": "x" * (MAX_CHAT_MESSAGE_CHARS + 1)})
    assert resp.status_code == 422
