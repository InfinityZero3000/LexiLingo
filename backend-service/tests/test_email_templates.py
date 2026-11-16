import re
from pathlib import Path
from unittest.mock import patch

import pytest

from app.core.config import settings
from app.services.email_service import EmailService

TEMPLATES = Path(__file__).resolve().parents[1] / "app" / "templates"
TO = "nhthang.dev@gmail.com"

SENDERS = {
    "verification_email": lambda: EmailService.send_verification_email(TO, "t", "Minh Anh"),
    "password_reset_email": lambda: EmailService.send_password_reset_email(
        to_email=TO, reset_token="t", display_name="Minh Anh"
    ),
    "vocabulary_review_reminder": lambda: EmailService.send_vocabulary_review_reminder_email(
        to_email=TO, display_name="Minh Anh", due_count=12
    ),
    "welcome_email": lambda: EmailService.send_welcome_email(to_email=TO, display_name="Minh Anh"),
    "password_changed_email": lambda: EmailService.send_password_changed_email(
        to_email=TO, display_name="Minh Anh"
    ),
    "weekly_summary_email": lambda: EmailService.send_weekly_summary_email(
        to_email=TO,
        display_name="Minh Anh",
        xp=1280,
        streak_days=6,
        words_learned=42,
        suggestion_title="IELTS Foundation",
        suggestion_link="https://lexilingo.me/courses/ielts",
    ),
    "streak_at_risk_email": lambda: EmailService.send_streak_at_risk_email(
        to_email=TO, display_name="Minh Anh", streak_days=6
    ),
}


@pytest.fixture
def smtp(monkeypatch):
    for name, value in {
        "SMTP_HOST": "smtp.test",
        "SMTP_USERNAME": "u",
        "SMTP_PASSWORD": "p",
        "SMTP_USE_SSL": False,
    }.items():
        monkeypatch.setattr(settings, name, value)
    with patch("app.services.email_service.smtplib.SMTP", autospec=True) as client:
        yield client


@pytest.fixture
def sent(smtp):
    return smtp.return_value.__enter__.return_value.send_message


def _html(message) -> str:
    return next(p.get_content() for p in message.walk() if p.get_content_type() == "text/html")


@pytest.mark.asyncio
@pytest.mark.parametrize("template", SENDERS)
async def test_every_template_is_plain_text_plus_html_with_hosted_images(sent, template):
    assert await SENDERS[template]() is True

    message = sent.call_args.args[0]
    parts = [p.get_content_type() for p in message.walk() if not p.is_multipart()]
    assert parts == ["text/plain", "text/html"], "an image part shows up as an attachment in Gmail"

    html = _html(message)
    base = settings.EMAIL_ASSET_BASE_URL.rstrip("/")
    assert "cid:" not in html
    assert f'src="{base}/hero_{template}.jpg"' in html
    assert f'src="{base}/footer.jpg"' in html
    assert not re.findall(r"\{[a-z_]+\}", html), "a placeholder was never filled"
    assert not re.findall(r"\{[a-z_]+\}", message.get_body(("plain",)).get_content())


@pytest.mark.parametrize("template", SENDERS)
def test_every_template_has_its_hero_image(template):
    assert (TEMPLATES / "assets" / f"hero_{template}.jpg").is_file()
    assert (TEMPLATES / "assets" / "footer.jpg").is_file()


@pytest.mark.asyncio
async def test_display_name_is_escaped_in_the_new_templates(sent):
    await EmailService.send_welcome_email(to_email=TO, display_name="<script>alert(1)</script>")

    html = _html(sent.call_args.args[0])
    assert "<script>" not in html
    assert "&lt;script&gt;" in html


@pytest.mark.asyncio
async def test_weekly_summary_without_a_suggestion_has_no_empty_block(sent):
    await EmailService.send_weekly_summary_email(
        to_email=TO, display_name=None, xp=0, streak_days=0, words_learned=0
    )

    message = sent.call_args.args[0]
    assert "Up next for you" not in _html(message)
    assert "Hi Learner" in message.get_body(("plain",)).get_content()


@pytest.mark.asyncio
async def test_promotional_mails_carry_list_unsubscribe(sent):
    await SENDERS["weekly_summary_email"]()
    weekly = sent.call_args.args[0]
    await SENDERS["streak_at_risk_email"]()
    streak = sent.call_args.args[0]

    assert weekly["List-Unsubscribe"].endswith("/settings>")
    assert streak["List-Unsubscribe"].endswith("/settings>")


@pytest.mark.asyncio
async def test_streak_subject_uses_singular_for_one_day(sent):
    await EmailService.send_streak_at_risk_email(to_email=TO, display_name="A", streak_days=1)

    assert sent.call_args.args[0]["Subject"] == "Your 1-day streak ends tonight"
    assert "1 day in a row" in _html(sent.call_args.args[0])


@pytest.mark.asyncio
async def test_new_mails_to_a_fake_address_never_reach_smtp(smtp):
    assert await EmailService.send_welcome_email(to_email="demo_3@lexilingo.dev", display_name="A") is False
    assert await EmailService.send_password_changed_email(to_email="a@example.com", display_name="A") is False
    smtp.assert_not_called()


@pytest.mark.asyncio
async def test_email_assets_are_served_by_the_backend(async_client):
    response = await async_client.get("/email-assets/footer.jpg")

    assert response.status_code == 200
    assert response.headers["content-type"] == "image/jpeg"


@pytest.mark.asyncio
@pytest.mark.parametrize("day,subject", [(1, "Your first LexiLingo lesson takes five minutes"), (3, "Still want to start with LexiLingo?")])
async def test_activation_nudge_links_to_the_start_route_and_borrows_the_welcome_hero(sent, day, subject):
    assert await EmailService.send_activation_nudge_email(
        to_email=TO, display_name="Minh Anh", day=day, start_link="https://lexilingo.me/courses"
    ) is True

    message = sent.call_args.args[0]
    html = _html(message)
    assert message["Subject"] == subject
    assert message["List-Unsubscribe"].endswith("/settings>")
    assert 'href="https://lexilingo.me/courses"' in html
    assert f'src="{settings.EMAIL_ASSET_BASE_URL.rstrip("/")}/hero_welcome_email.jpg"' in html
    assert not re.findall(r"\{[a-z_]+\}", html)
    assert "https://lexilingo.me/courses" in message.get_body(("plain",)).get_content()
