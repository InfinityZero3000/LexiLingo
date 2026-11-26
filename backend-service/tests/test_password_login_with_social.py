"""Password accounts are the backend's own: Firebase settings and social sign-in must not break them."""

from unittest.mock import patch

import pytest

from app.services.email_service import EmailService

BASE = "/api/v1/auth"
EMAIL = "learner@example.com"
PASSWORD = "Str0ng!Passw0rd-1"
NEW_PASSWORD = "Str0ng!Passw0rd-2"


@pytest.fixture(autouse=True)
def _no_mail():
    with patch.object(EmailService, "send_verification_email", autospec=True), patch.object(
        EmailService, "send_password_changed_email", autospec=True
    ), patch.object(EmailService, "send_welcome_email", autospec=True):
        yield


@pytest.fixture
def firebase_is_never_called():
    with patch(
        "app.core.firebase_auth.verify_firebase_token",
        autospec=True,
        side_effect=AssertionError("password sign-in must not use Firebase"),
    ):
        yield


async def _register(client):
    response = await client.post(
        f"{BASE}/register",
        json={"email": EMAIL, "username": "learner", "password": PASSWORD},
    )
    assert response.status_code == 201, response.text


async def _login(client, password=PASSWORD) -> int:
    response = await client.post(f"{BASE}/login", json={"email": EMAIL, "password": password})
    return response.status_code


async def _facebook(client, *, verified: bool):
    claims = {
        "email": EMAIL,
        "email_verified": verified,
        "firebase": {"sign_in_provider": "facebook.com"},
    }
    with patch("app.core.firebase_auth.verify_firebase_token", autospec=True, return_value=claims):
        return await client.post(
            f"{BASE}/facebook", json={"id_token": "firebase-token", "source": "app"}
        )


async def _verify_email(db_session):
    from sqlalchemy import update

    from app.models.user import User

    await db_session.execute(update(User).where(User.email == EMAIL).values(is_verified=True))
    await db_session.commit()
    db_session.expire_all()


async def test_register_and_password_login_do_not_depend_on_firebase(
    async_client, firebase_is_never_called
):
    await _register(async_client)

    assert await _login(async_client) == 200
    assert await _login(async_client, "wrong-password-1A!") == 401


async def test_a_refused_facebook_attempt_leaves_the_password_working(async_client):
    await _register(async_client)

    refused = await _facebook(async_client, verified=False)

    assert refused.status_code == 400
    assert "existing method" in refused.text
    assert await _login(async_client) == 200


async def test_linking_facebook_to_a_verified_account_keeps_the_password(
    async_client, db_session
):
    await _register(async_client)
    await _verify_email(db_session)

    linked = await _facebook(async_client, verified=True)

    assert linked.status_code == 200, linked.text
    assert await _login(async_client) == 200


async def test_an_owner_whose_unproven_password_was_dropped_can_set_a_new_one(async_client):
    await _register(async_client)
    google = {"email": EMAIL, "email_verified": True, "name": "Learner", "picture": None}
    with patch("app.core.security.verify_google_token", autospec=True, return_value=google):
        signed_in = await async_client.post(
            f"{BASE}/google", json={"id_token": "google-token", "source": "app"}
        )
    assert signed_in.status_code == 200, signed_in.text
    assert await _login(async_client) == 401

    with patch.object(EmailService, "send_password_reset_email", autospec=True) as mail:
        await async_client.post(f"{BASE}/forgot-password", json={"email": EMAIL})
    reset = await async_client.post(
        f"{BASE}/reset-password",
        json={"token": mail.call_args.kwargs["reset_token"], "new_password": NEW_PASSWORD},
    )

    assert reset.status_code == 200, reset.text
    assert await _login(async_client, NEW_PASSWORD) == 200
