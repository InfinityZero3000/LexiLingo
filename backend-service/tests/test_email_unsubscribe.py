import re
import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

import pytest
from sqlalchemy import select

from app.core.config import settings
from app.models.progress import DailyActivity
from app.models.reminder import UserReminderPreference
from app.models.user import User
from app.services import email_unsubscribe as unsub
from app.services import nurture_service as nurture
from app.services.email_service import EmailService
from app.services.push_notification_service import PushNotificationService

NOW = datetime(2026, 11, 16, 13, 30, tzinfo=timezone.utc)
PATH = f"{settings.API_V1_PREFIX}/email/unsubscribe"


async def make_user(db, name, *, age_hours=30) -> User:
    user = User(
        email=f"{name}@gmail.com",
        username=name,
        hashed_password="x",
        display_name=name,
        is_active=True,
        is_verified=True,
        created_at=NOW - timedelta(hours=age_hours),
    )
    db.add(user)
    await db.commit()
    return user


async def opted_in(db, user) -> bool:
    row = (
        await db.execute(select(UserReminderPreference).where(UserReminderPreference.user_id == user.id))
    ).scalar_one_or_none()
    return row is None or row.nurture_emails_enabled


def test_token_round_trips_and_carries_no_expiry():
    uid = uuid.uuid4()
    token = unsub.make_token(uid)

    assert unsub.read_token(token) == (uid, unsub.NURTURE)
    assert re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", token)


def test_tampered_or_foreign_tokens_are_refused():
    uid = uuid.uuid4()
    body, sig = unsub.make_token(uid).split(".")
    other = unsub.make_token(uuid.uuid4()).split(".")[0]

    # Change the last character to one it is not; "AA" was the signature 1 time in 4096.
    tampered = sig[:-1] + ("B" if sig[-1] != "B" else "C")
    for bad in ("", "x", "a.b", f"{other}.{sig}", f"{body}.{tampered}", f"{body}.{sig}.x", "é.é"):
        assert unsub.read_token(bad) is None


def test_an_access_token_is_not_an_unsubscribe_token():
    from app.core.security import create_verification_token

    assert unsub.read_token(create_verification_token({"sub": str(uuid.uuid4()), "purpose": "email_unsubscribe"})) is None


def test_rotating_the_secret_revokes_issued_tokens(monkeypatch):
    uid = uuid.uuid4()
    token = unsub.make_token(uid)

    monkeypatch.setattr(settings, "EMAIL_UNSUBSCRIBE_SECRET", "rotated-secret")

    assert unsub.read_token(token) is None
    assert unsub.read_token(unsub.make_token(uid)) == (uid, unsub.NURTURE)


@pytest.mark.asyncio
async def test_get_confirms_without_changing_anything(async_client, db_session):
    user = await make_user(db_session, "scanner")

    response = await async_client.get(f"{PATH}?token={unsub.make_token(user.id)}")

    assert response.status_code == 200
    assert 'method="post"' in response.text
    assert "default-src 'none'" in response.headers["content-security-policy"]
    assert await opted_in(db_session, user)


@pytest.mark.asyncio
async def test_post_unsubscribes_without_cookies_or_login_and_is_idempotent(async_client, db_session):
    user = await make_user(db_session, "oneclick")
    url = f"{PATH}?token={unsub.make_token(user.id)}"

    first = await async_client.post(url, content="List-Unsubscribe=One-Click", headers={"content-type": "application/x-www-form-urlencoded"})
    second = await async_client.post(url)

    assert (first.status_code, second.status_code) == (200, 200)
    assert "unsubscribed" in first.text
    assert not await opted_in(db_session, user)
    assert not first.headers.get("set-cookie")


@pytest.mark.asyncio
async def test_post_keeps_an_existing_preference_row_untouched_otherwise(async_client, db_session):
    user = await make_user(db_session, "haspref")
    db_session.add(UserReminderPreference(user_id=user.id, enabled=True, email_enabled=True, min_due_count=4))
    await db_session.commit()

    await async_client.post(f"{PATH}?token={unsub.make_token(user.id)}")

    row = (await db_session.execute(select(UserReminderPreference).where(UserReminderPreference.user_id == user.id))).scalar_one()
    await db_session.refresh(row)
    assert (row.nurture_emails_enabled, row.email_enabled, row.min_due_count) == (False, True, 4)


@pytest.mark.asyncio
@pytest.mark.parametrize("method", ["get", "post"])
async def test_bad_token_is_a_generic_400_page(async_client, db_session, method):
    user = await make_user(db_session, f"victim{method}")
    good = unsub.make_token(user.id)

    for token in ("", "garbage", good[:-3] + "AAA"):
        response = await getattr(async_client, method)(f"{PATH}?token={token}")
        assert response.status_code == 400
        assert "not valid" in response.text
        assert user.email not in response.text
    assert await opted_in(db_session, user)


@pytest.mark.asyncio
async def test_a_valid_token_for_a_deleted_account_looks_like_success(async_client):
    response = await async_client.post(f"{PATH}?token={unsub.make_token(uuid.uuid4())}")

    assert response.status_code == 200


@pytest.mark.asyncio
async def test_other_routes_keep_the_default_csp(async_client):
    response = await async_client.get("/email-assets/footer.jpg")

    assert response.headers["content-security-policy"].startswith("default-src 'self'")


@pytest.fixture
def smtp(monkeypatch):
    for name, value in {"SMTP_HOST": "smtp.test", "SMTP_USERNAME": "u", "SMTP_PASSWORD": "p", "SMTP_USE_SSL": False}.items():
        monkeypatch.setattr(settings, name, value)
    monkeypatch.setattr(settings, "NURTURE_EMAILS_ENABLED", True)
    monkeypatch.setattr(settings, "NURTURE_SEND_DELAY_SECONDS", 0)
    monkeypatch.setattr(settings, "NURTURE_STREAK_LOCAL_HOUR", 20)
    with patch("app.services.email_service.smtplib.SMTP", autospec=True) as client:
        yield client.return_value.__enter__.return_value.send_message


def _unsubscribe_target(message) -> str:
    return re.search(r"<(https://[^>]+)>", message["List-Unsubscribe"]).group(1)


@pytest.mark.asyncio
async def test_every_nurture_email_carries_working_one_click_headers_and_a_footer_link(db_session, smtp, monkeypatch):
    from tests.test_nurture_service import _streaker

    monkeypatch.setattr(settings, "EMAIL_REPLY_TO", "support@lexilingo.me")
    monkeypatch.setattr(PushNotificationService, "send_nurture", _no_push, raising=True)
    new = await make_user(db_session, "newbie")
    streaker = await _streaker(db_session, "streaker")
    db_session.add(DailyActivity(user_id=streaker.id, activity_date=date(2026, 11, 14), xp_earned=100))
    await db_session.commit()

    await nurture.run_activation(db_session, nurture.D1, NOW)
    await nurture.run_streak_risk(db_session, NOW)
    await nurture.run_weekly(db_session, NOW)

    seen = {}
    for call in smtp.call_args_list:
        message = call.args[0]
        seen[message["Subject"]] = message
    assert len(seen) >= 3
    owners = {new.id, streaker.id}
    for message in seen.values():
        header = message["List-Unsubscribe"]
        assert header.endswith("<mailto:support@lexilingo.me?subject=unsubscribe>")
        assert message["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
        target = _unsubscribe_target(message)
        assert urlparse(target).path == PATH
        token = parse_qs(urlparse(target).query)["token"][0]
        assert unsub.read_token(token)[0] in owners
        for part in message.walk():
            if part.get_content_type() in ("text/html", "text/plain"):
                assert target in part.get_content()
        html_part = next(p.get_content() for p in message.walk() if p.get_content_type() == "text/html")
        # Worded in the learner's language; what matters is a visible link to it.
        assert re.search(r'<a href="[^"]*/email/unsubscribe\?token=[^"]*"[^>]*>[^<]+</a>', html_part)


async def _no_push(self, **kwargs):
    return False


@pytest.mark.asyncio
async def test_mailto_is_offered_only_when_a_real_address_is_configured(smtp, monkeypatch):
    monkeypatch.setattr(settings, "EMAIL_REPLY_TO", None)

    await EmailService.send_streak_at_risk_email(
        to_email="a@gmail.com", display_name="A", user_id=uuid.uuid4(), streak_days=3
    )

    assert "mailto" not in smtp.call_args.args[0]["List-Unsubscribe"]


@pytest.mark.asyncio
async def test_the_link_in_a_sent_email_unsubscribes_and_the_next_run_skips_the_learner(async_client, db_session, smtp, monkeypatch):
    monkeypatch.setattr(PushNotificationService, "send_nurture", _no_push, raising=True)
    user = await make_user(db_session, "leaver")
    await nurture.run_activation(db_session, nurture.D1, NOW)
    target = _unsubscribe_target(smtp.call_args.args[0])
    sent_before = smtp.call_count

    response = await async_client.post(urlparse(target).path + "?" + urlparse(target).query)
    assert response.status_code == 200
    assert user.id not in {r.user_id for r in await nurture.select_activation(db_session, nurture.D1, NOW)}
    other = await make_user(db_session, "stayer")
    await nurture.run_activation(db_session, nurture.D1, NOW)

    recipients = [c.args[0]["To"] for c in smtp.call_args_list[sent_before:]]
    assert recipients == [other.email]
