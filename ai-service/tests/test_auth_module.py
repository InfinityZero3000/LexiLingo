import os

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from jose import jwt

from api.core.auth import _decode_backend_jwt, get_current_user


@pytest.mark.asyncio
async def test_get_current_user_accepts_valid_access_token(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv("ALGORITHM", "HS256")

    token = jwt.encode(
        {"sub": "user-123", "type": "access"},
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
        {"sub": "user-123", "type": "refresh"},
        os.environ["SECRET_KEY"],
        algorithm=os.environ["ALGORITHM"],
    )

    assert _decode_backend_jwt(refresh_token) is None
