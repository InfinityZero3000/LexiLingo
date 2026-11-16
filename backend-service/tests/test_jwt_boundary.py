"""Negative JWT boundary tests — audit item #5.

Crafts tokens with a *correctly matching signature* (same SECRET_KEY /
ALGORITHM as the app) but a wrong audience, issuer, or type, to prove
`decode_token` / `get_current_user` reject them on claims, not just on
signature. No mocking of the verification path itself.
"""

from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
import jwt
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    decode_verification_token,
    is_locally_issued_token,
)


def _sign(claims: dict) -> str:
    return jwt.encode(claims, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def _base_claims(**overrides) -> dict:
    claims = {
        "sub": "00000000-0000-0000-0000-000000000001",
        "type": "access",
        "iss": settings.JWT_ISSUER,
        "aud": settings.JWT_AUDIENCE,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
    }
    claims.update(overrides)
    return claims


def test_correctly_signed_token_with_wrong_audience_is_rejected():
    token = _sign(_base_claims(aud="some-other-service"))
    assert decode_token(token) is None


def test_correctly_signed_token_with_wrong_issuer_is_rejected():
    token = _sign(_base_claims(iss="not-lexilingo-backend"))
    assert decode_token(token) is None


def test_correctly_signed_expired_token_is_rejected():
    token = _sign(
        _base_claims(
            iat=datetime.now(timezone.utc) - timedelta(minutes=10),
            exp=datetime.now(timezone.utc) - timedelta(minutes=1),
        )
    )
    assert decode_token(token) is None


def test_token_signed_with_a_different_key_is_rejected():
    """Same claims, different signing key — the signature check itself."""
    forged = jwt.encode(_base_claims(), "not-the-real-secret-key", algorithm=settings.ALGORITHM)
    assert decode_token(forged) is None


def test_genuinely_issued_access_token_round_trips():
    token = create_access_token({"sub": "00000000-0000-0000-0000-000000000001"})
    payload = decode_token(token)
    assert payload is not None
    assert payload["aud"] == settings.JWT_AUDIENCE
    assert payload["iss"] == settings.JWT_ISSUER
    assert payload["type"] == "access"


@pytest.mark.asyncio
async def test_get_current_user_rejects_wrong_audience_despite_valid_signature(
    db_session: AsyncSession,
):
    token = _sign(_base_claims(aud="some-other-service"))
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(credentials=credentials, db=db_session)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_get_current_user_rejects_refresh_token_used_as_access_token(
    db_session: AsyncSession, test_user
):
    refresh_token = create_refresh_token({"sub": str(test_user.id)})
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=refresh_token)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(credentials=credentials, db=db_session)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_refresh_endpoint_rejects_access_token_used_as_refresh_token(async_client):
    access_token = create_access_token({"sub": "00000000-0000-0000-0000-000000000001"})

    response = await async_client.post(
        f"{settings.API_V1_PREFIX}/auth/refresh",
        json={"refresh_token": access_token},
    )

    assert response.status_code == 401
    assert "token type" in response.json()["error"]["message"].lower()


@pytest.mark.asyncio
async def test_refresh_endpoint_rejects_wrong_audience_refresh_token(async_client):
    forged_refresh = _sign(_base_claims(type="refresh", aud="some-other-service"))

    response = await async_client.post(
        f"{settings.API_V1_PREFIX}/auth/refresh",
        json={"refresh_token": forged_refresh},
    )

    assert response.status_code == 401


# Minted once by python-jose 3.5.0 (HS256) before the PyJWT switch; they must keep verifying.
_JOSE_SECRET = "compat-test-secret-0123456789abcdef"
_JOSE_ACCESS = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoiYWNjZXNzIiwiaXNzIjoibGV4aWxpbmdvLWJhY2tlbmQiLCJhdWQiOiJsZXhpbGluZ28tc2VydmljZXMiLCJpYXQiOjE3MDAwMDAwMDAsImp0aSI6IjAxMjM0NTY3ODlhYmNkZWYwMTIzNDU2Nzg5YWJjZGVmIiwiZXhwIjo0MTAyNDQ0ODAwfQ.B-p_QwhWQ09_CWyaFCd_0d2wWETXft6wzg-ZEVzAGA8"
_JOSE_EXPIRED = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoiYWNjZXNzIiwiaXNzIjoibGV4aWxpbmdvLWJhY2tlbmQiLCJhdWQiOiJsZXhpbGluZ28tc2VydmljZXMiLCJpYXQiOjE3MDAwMDAwMDAsImp0aSI6IjAxMjM0NTY3ODlhYmNkZWYwMTIzNDU2Nzg5YWJjZGVmIiwiZXhwIjoxNzAwMDAwMzAwfQ.ZAjLVtoPCXkt76dNTwAB89-PQUt39lJjYC19IsghNJk"
_JOSE_WRONG_SIGNATURE = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoiYWNjZXNzIiwiaXNzIjoibGV4aWxpbmdvLWJhY2tlbmQiLCJhdWQiOiJsZXhpbGluZ28tc2VydmljZXMiLCJpYXQiOjE3MDAwMDAwMDAsImp0aSI6IjAxMjM0NTY3ODlhYmNkZWYwMTIzNDU2Nzg5YWJjZGVmIiwiZXhwIjo0MTAyNDQ0ODAwfQ.1mqU4UcT4LnpYPjhC8YSAR1E1ZQkXsYMvuxlIEdunwk"
_JOSE_VERIFICATION = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJ0eXBlIjoidmVyaWZpY2F0aW9uIiwicHVycG9zZSI6InBhc3N3b3JkX3Jlc2V0IiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjQxMDI0NDQ4MDB9.izaVHONHdsHvoCuqzKKJ0R_3ymjgxPFtGbCcaERbJME"


@pytest.fixture
def jose_secret(monkeypatch):
    monkeypatch.setattr(settings, "SECRET_KEY", _JOSE_SECRET)
    monkeypatch.setattr(settings, "ALGORITHM", "HS256")


def test_token_minted_by_python_jose_still_verifies(jose_secret):
    payload = decode_token(_JOSE_ACCESS)
    assert payload is not None
    assert payload["sub"] == "00000000-0000-0000-0000-000000000001"
    assert payload["type"] == "access"
    assert is_locally_issued_token(_JOSE_ACCESS)


def test_expired_python_jose_token_is_rejected(jose_secret):
    assert decode_token(_JOSE_EXPIRED) is None


def test_python_jose_token_with_wrong_signature_is_rejected(jose_secret):
    assert decode_token(_JOSE_WRONG_SIGNATURE) is None


def test_python_jose_verification_token_still_verifies(jose_secret):
    assert decode_verification_token(_JOSE_VERIFICATION, "password_reset") == (
        "00000000-0000-0000-0000-000000000001"
    )
    assert decode_verification_token(_JOSE_VERIFICATION, "email_verify") is None
    assert decode_token(_JOSE_VERIFICATION) is None


def test_unsigned_and_garbage_tokens_are_rejected(jose_secret):
    unsigned = jwt.encode(_base_claims(), None, algorithm="none")
    assert decode_token(unsigned) is None
    assert decode_token("not-a-jwt") is None
    assert not is_locally_issued_token("not-a-jwt")
