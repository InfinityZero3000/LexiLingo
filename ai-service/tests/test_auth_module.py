import os

import pytest
from fastapi import FastAPI
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from httpx import ASGITransport, AsyncClient
from jose import jwt

from api.core.auth import _decode_backend_jwt, _jwt_secret, get_current_user
from api.routes import ai as ai_route
from api.routes import chat as chat_route


@pytest.mark.asyncio
async def test_get_current_user_accepts_valid_access_token(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv("ALGORITHM", "HS256")

    token = jwt.encode(
        {
            "sub": "user-123",
            "type": "access",
            "iss": "lexilingo-backend",
            "aud": "lexilingo-services",
        },
        os.environ["SECRET_KEY"],
        algorithm=os.environ["ALGORITHM"],
    )
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    user = await get_current_user(credentials=credentials)

    assert user.user_id == "user-123"
    assert user.token_type == "access"


@pytest.mark.asyncio
async def test_get_current_user_rejects_missing_or_invalid_token(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv("ALGORITHM", "HS256")

    with pytest.raises(HTTPException) as missing_exc:
        await get_current_user(credentials=None)
    assert missing_exc.value.status_code == 401

    bad_credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="not-a-jwt",
    )
    with pytest.raises(HTTPException) as invalid_exc:
        await get_current_user(credentials=bad_credentials)
    assert invalid_exc.value.status_code == 401


def test_decode_backend_jwt_requires_access_token_type(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv("ALGORITHM", "HS256")

    refresh_token = jwt.encode(
        {
            "sub": "user-123",
            "type": "refresh",
            "iss": "lexilingo-backend",
            "aud": "lexilingo-services",
        },
        os.environ["SECRET_KEY"],
        algorithm=os.environ["ALGORITHM"],
    )

    assert _decode_backend_jwt(refresh_token) is None


def test_jwt_secret_does_not_accept_legacy_aliases(monkeypatch):
    monkeypatch.delenv("SECRET_KEY", raising=False)
    monkeypatch.setenv("JWT_SECRET_KEY", "legacy-secret")
    monkeypatch.setenv("AI_JWT_SECRET_KEY", "legacy-ai-secret")

    assert _jwt_secret() == ""


@pytest.mark.asyncio
async def test_legacy_chat_routes_require_bearer_token():
    app = FastAPI()
    app.include_router(chat_route.router, prefix="/api/v1/chat")

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/v1/chat/sessions",
            json={"user_id": "user-123", "title": "Test"},
        )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_legacy_ai_analyze_requires_bearer_token():
    app = FastAPI()
    app.include_router(ai_route.router, prefix="/api/v1/ai")

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            "/api/v1/ai/trace-cag/analyze",
            json={"text": "hello", "session_id": "s1"},
        )

    assert response.status_code == 401
