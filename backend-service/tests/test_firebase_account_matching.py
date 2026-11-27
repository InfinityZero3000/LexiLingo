"""Who a Firebase token may sign in as: a genuine token does not prove its email."""

from unittest.mock import patch

import pytest
from sqlalchemy import select

from app.core.config import settings
from app.core.firebase_auth import get_or_create_user_from_claims
from app.models.user import RefreshToken, User


def _claims(email: str, provider: str, *, verified: bool) -> dict:
    return {
        "email": email,
        "uid": "firebase-uid",
        "name": "Someone",
        "email_verified": verified,
        "firebase": {"sign_in_provider": provider},
    }


async def _account(db, email: str, providers: list[str], *, verified: bool) -> User:
    user = User(
        email=email,
        username=email.split("@")[0],
        hashed_password="original-hash",
        provider=providers,
        is_verified=verified,
        is_active=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest.mark.parametrize("provider", ["password", "anonymous", "github.com", None])
@pytest.mark.parametrize("verified", [True, False])
async def test_a_sign_in_method_the_app_does_not_offer_is_refused(db_session, provider, verified):
    await _account(db_session, "victim@example.com", ["local"], verified=True)

    for email in ("victim@example.com", "nobody@example.com"):
        with pytest.raises(ValueError):
            await get_or_create_user_from_claims(
                db_session, _claims(email, provider, verified=verified)
            )


@pytest.mark.parametrize("providers", [["local"], ["google"], ["local", "google"]])
@pytest.mark.parametrize("provider", ["facebook.com", "google.com"])
async def test_an_unverified_email_cannot_enter_an_existing_account(db_session, providers, provider):
    user = await _account(db_session, "victim@example.com", providers, verified=True)

    with pytest.raises(ValueError):
        await get_or_create_user_from_claims(
            db_session, _claims(user.email, provider, verified=False)
        )
    await db_session.refresh(user)
    assert user.provider == providers


async def test_facebook_can_create_an_account_and_return_to_it(db_session):
    claims = _claims("new@example.com", "facebook.com", verified=False)

    first = await get_or_create_user_from_claims(db_session, claims)
    second = await get_or_create_user_from_claims(db_session, claims)

    assert second.id == first.id
    assert first.provider == ["facebook"]
    assert first.is_verified is False


async def test_only_facebook_may_open_an_account_without_a_verified_email(db_session):
    with pytest.raises(ValueError):
        await get_or_create_user_from_claims(
            db_session, _claims("new@example.com", "google.com", verified=False)
        )


async def test_a_linked_account_gains_facebook_once_the_email_is_verified(db_session):
    user = await _account(db_session, "owner@example.com", ["google"], verified=True)

    signed_in = await get_or_create_user_from_claims(
        db_session, _claims(user.email, "facebook.com", verified=True)
    )

    assert signed_in.id == user.id
    assert signed_in.provider == ["google", "facebook"]
    assert signed_in.hashed_password == "original-hash"


@pytest.mark.parametrize("providers", [["local"], ["facebook"]])
async def test_the_proven_owner_shuts_out_whoever_registered_the_address(db_session, providers):
    user = await _account(db_session, "owner@example.com", providers, verified=False)
    token = RefreshToken(
        user_id=user.id,
        token="squatter-session",
        expires_at=user.created_at.replace(year=user.created_at.year + 1),
    )
    db_session.add(token)
    await db_session.commit()

    owner = await get_or_create_user_from_claims(
        db_session, _claims(user.email, "google.com", verified=True)
    )

    revoked = await db_session.scalar(
        select(RefreshToken.is_revoked).where(RefreshToken.id == token.id)
    )
    assert owner.is_verified is True
    assert "facebook" not in owner.provider
    assert revoked is True
    if "local" in providers:
        assert owner.hashed_password != "original-hash"


async def test_an_unverified_email_never_earns_an_admin_role(db_session):
    with patch.object(
        type(settings), "get_admin_role_for_email", autospec=True, return_value="admin"
    ), patch("app.core.firebase_auth._get_role_id", autospec=True, return_value=None) as role_id:
        await get_or_create_user_from_claims(
            db_session, _claims("boss@example.com", "facebook.com", verified=False)
        )

    assert [call.args[1] for call in role_id.call_args_list] == ["user"]


async def test_the_facebook_route_refuses_another_providers_token(async_client):
    claims = _claims("victim@example.com", "password", verified=False)
    with patch("app.core.firebase_auth.verify_firebase_token", autospec=True, return_value=claims):
        response = await async_client.post(
            "/api/v1/auth/facebook", json={"id_token": "genuine-token", "source": "app"}
        )
    assert response.status_code == 401


async def test_google_still_signs_in_someone_who_started_with_facebook(async_client, db_session):
    user = await _account(db_session, "starter@example.com", ["facebook"], verified=False)
    google = {"email": user.email, "email_verified": True, "name": "Starter", "picture": None}

    with patch("app.core.security.verify_google_token", autospec=True, return_value=google):
        response = await async_client.post(
            "/api/v1/auth/google", json={"id_token": "google-token", "source": "app"}
        )

    assert response.status_code == 200, response.text
    await db_session.refresh(user)
    assert user.provider == ["google"]
    assert user.is_verified is True
