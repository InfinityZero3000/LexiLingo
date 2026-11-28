"""An email that already has an account: ask the owner to merge, never merge by itself."""
from unittest.mock import patch

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.user import User

LINK = "/api/v1/auth/facebook/link"
LOGIN = "/api/v1/auth/facebook"


def _claims(email: str, provider: str = "facebook.com", *, verified: bool = False) -> dict:
    return {"email": email, "uid": "fb-uid", "name": "Someone", "email_verified": verified,
            "firebase": {"sign_in_provider": provider}}


async def _account(db: AsyncSession, email: str, providers: list[str]) -> User:
    user = User(email=email, username=email.split("@")[0], hashed_password="x",
                provider=providers, is_verified=True, is_active=True)
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


def _bearer(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token({'sub': str(user.id)})}"}


def _token(claims: dict | None):
    return patch("app.core.firebase_auth.verify_firebase_token", autospec=True, return_value=claims)


@pytest.mark.parametrize(
    "providers,methods",
    [(["google"], ["google"]), (["local"], ["password"]),
     (["local", "google"], ["google", "password"]), ([], ["password"])],
)
async def test_the_refusal_says_how_the_owner_can_prove_the_account(
    providers, methods, async_client: AsyncClient, db_session: AsyncSession
):
    await _account(db_session, "owner@example.com", providers)

    with _token(_claims("owner@example.com")):
        response = await async_client.post(LOGIN, json={"id_token": "t"})

    assert response.status_code == 400, response.text
    error = response.json()["error"]
    assert error["details"] == {"reason": "account_link_required", "methods": methods}
    # Apps already installed recognise the sentence, not the reason.
    assert "login with your existing method" in error["message"]


async def test_after_the_owner_merges_facebook_signs_in(
    async_client: AsyncClient, db_session: AsyncSession
):
    user = await _account(db_session, "owner@example.com", ["local"])
    headers, user_id = _bearer(user), str(user.id)

    with _token(_claims("Owner@Example.com")):
        linked = await async_client.post(LINK, json={"id_token": "t"}, headers=headers)
        again = await async_client.post(LINK, json={"id_token": "t"}, headers=headers)
    assert (linked.status_code, again.status_code) == (200, 200), linked.text

    await db_session.refresh(user)
    assert user.provider == ["local", "facebook"]

    with _token(_claims("owner@example.com")):
        signed_in = await async_client.post(LOGIN, json={"id_token": "t"})
    assert signed_in.status_code == 200, signed_in.text
    assert signed_in.json()["user_id"] == user_id


@pytest.mark.parametrize(
    "claims,status,reason",
    [
        (_claims("someone-else@example.com"), 400, "email_mismatch"),
        (_claims("owner@example.com", "google.com", verified=True), 401, None),
        (None, 401, None),
    ],
)
async def test_only_a_facebook_token_for_the_same_email_is_merged(
    claims, status, reason, async_client: AsyncClient, db_session: AsyncSession
):
    user = await _account(db_session, "owner@example.com", ["local"])

    with _token(claims):
        response = await async_client.post(LINK, json={"id_token": "t"}, headers=_bearer(user))

    assert response.status_code == status, response.text
    if reason:
        assert response.json()["error"]["details"]["reason"] == reason
    await db_session.refresh(user)
    assert user.provider == ["local"]


async def test_merging_needs_a_signed_in_owner(async_client: AsyncClient):
    response = await async_client.post(LINK, json={"id_token": "t"})

    assert response.status_code == 401


def test_the_auth_emulator_is_refused_in_production(monkeypatch: pytest.MonkeyPatch):
    """The Admin SDK accepts unsigned tokens from an emulator: anyone could be anyone."""
    from app.core import firebase_auth
    from app.core.config import settings

    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "127.0.0.1:9099")
    monkeypatch.setattr(settings, "APP_ENV", "production")

    # The SDK itself would accept it, so only our own check can refuse.
    with patch.object(firebase_auth, "_init_firebase_app", autospec=True), \
            patch.object(firebase_auth.firebase_auth, "verify_id_token", return_value=_claims("a@b.com")):
        assert firebase_auth.verify_firebase_token("unsigned") is None
