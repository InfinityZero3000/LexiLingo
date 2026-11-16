import os

import pytest
from fastapi import FastAPI
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from httpx import ASGITransport, AsyncClient
import jwt

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


# Minted once by python-jose 3.5.0 (HS256) before the PyJWT switch; they must keep verifying.
_JOSE_SECRET = "compat-test-secret-0123456789abcdef"
_JOSE_ACCESS = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoiYWNjZXNzIiwiaXNzIjoibGV4aWxpbmdvLWJhY2tlbmQiLCJhdWQiOiJsZXhpbGluZ28tc2VydmljZXMiLCJpYXQiOjE3MDAwMDAwMDAsImp0aSI6IjAxMjM0NTY3ODlhYmNkZWYwMTIzNDU2Nzg5YWJjZGVmIiwiZXhwIjo0MTAyNDQ0ODAwfQ.B-p_QwhWQ09_CWyaFCd_0d2wWETXft6wzg-ZEVzAGA8"
_JOSE_EXPIRED = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoiYWNjZXNzIiwiaXNzIjoibGV4aWxpbmdvLWJhY2tlbmQiLCJhdWQiOiJsZXhpbGluZ28tc2VydmljZXMiLCJpYXQiOjE3MDAwMDAwMDAsImp0aSI6IjAxMjM0NTY3ODlhYmNkZWYwMTIzNDU2Nzg5YWJjZGVmIiwiZXhwIjoxNzAwMDAwMzAwfQ.ZAjLVtoPCXkt76dNTwAB89-PQUt39lJjYC19IsghNJk"
_JOSE_WRONG_SIGNATURE = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoiYWNjZXNzIiwiaXNzIjoibGV4aWxpbmdvLWJhY2tlbmQiLCJhdWQiOiJsZXhpbGluZ28tc2VydmljZXMiLCJpYXQiOjE3MDAwMDAwMDAsImp0aSI6IjAxMjM0NTY3ODlhYmNkZWYwMTIzNDU2Nzg5YWJjZGVmIiwiZXhwIjo0MTAyNDQ0ODAwfQ.1mqU4UcT4LnpYPjhC8YSAR1E1ZQkXsYMvuxlIEdunwk"
_JOSE_VERIFICATION = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoidmVyaWZpY2F0aW9uIiwicHVycG9zZSI6InBhc3N3b3JkX3Jlc2V0IiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjQxMDI0NDQ4MDB9.izaVHONHdsHvoCuqzKKJ0R_3ymjgxPFtGbCcaERbJME"


def test_token_minted_by_python_jose_still_verifies(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", _JOSE_SECRET)
    monkeypatch.setenv("ALGORITHM", "HS256")

    payload = _decode_backend_jwt(_JOSE_ACCESS)

    assert payload is not None
    assert payload["sub"] == "00000000-0000-0000-0000-000000000001"


def test_expired_python_jose_token_is_rejected(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", _JOSE_SECRET)
    monkeypatch.setenv("ALGORITHM", "HS256")
    monkeypatch.setenv("AI_JWT_LEEWAY_SECONDS", "15")

    assert _decode_backend_jwt(_JOSE_EXPIRED) is None


def test_python_jose_token_with_wrong_signature_is_rejected(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", _JOSE_SECRET)
    monkeypatch.setenv("ALGORITHM", "HS256")

    assert _decode_backend_jwt(_JOSE_WRONG_SIGNATURE) is None


def test_wrong_audience_and_unsigned_tokens_are_rejected(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", _JOSE_SECRET)
    monkeypatch.setenv("ALGORITHM", "HS256")
    claims = {"sub": "u", "type": "access", "iss": "lexilingo-backend"}

    wrong_aud = jwt.encode({**claims, "aud": "someone-else"}, _JOSE_SECRET, algorithm="HS256")
    unsigned = jwt.encode({**claims, "aud": "lexilingo-services"}, None, algorithm="none")

    assert _decode_backend_jwt(wrong_aud) is None
    assert _decode_backend_jwt(unsigned) is None
