import re
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest

from app.core.config import settings
from app.services.email_service import EmailService

TEMPLATES = Path(__file__).resolve().parents[1] / "app" / "templates"
TO = "nhthang.dev@gmail.com"
UID = uuid.UUID("11111111-2222-3333-4444-555555555555")

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
        user_id=UID,
        xp=1280,
        streak_days=6,
        words_learned=42,
        suggestion_title="IELTS Foundation",
        suggestion_link="https://lexilingo.me/courses/ielts",
    ),
    "streak_at_risk_email": lambda: EmailService.send_streak_at_risk_email(
        to_email=TO, display_name="Minh Anh", user_id=UID, streak_days=6
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
    # The headline is HTML over a text-free image, so every mail shares one.
    assert f"url('{base}/hero.jpg')" in html and f'background="{base}/hero.jpg"' in html
    assert f'src="{base}/footer.jpg"' in html
    assert not re.findall(r"\{[a-z_]+\}", html), "a placeholder was never filled"
    assert not re.findall(r"\{[a-z_]+\}", message.get_body(("plain",)).get_content())


@pytest.mark.parametrize("template", SENDERS)
def test_mails_already_sent_keep_their_images(template):
    # Old mails link to the per-mail images; removing them breaks those mails.
    assert (TEMPLATES / "assets" / f"hero_{template}.jpg").is_file()
    assert (TEMPLATES / "assets" / "hero.jpg").is_file()
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
        to_email=TO, display_name=None, user_id=UID, xp=0, streak_days=0, words_learned=0
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

    for message in (weekly, streak):
        assert "/email/unsubscribe?token=" in message["List-Unsubscribe"]
        assert message["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"


@pytest.mark.asyncio
async def test_streak_subject_uses_singular_for_one_day(sent):
    await EmailService.send_streak_at_risk_email(to_email=TO, display_name="A", user_id=UID, streak_days=1)

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
    # Long-lived, so Cloudflare and Gmail's proxy serve repeat opens.
    assert response.headers["cache-control"] == "public, max-age=31536000, immutable"


@pytest.mark.asyncio
@pytest.mark.parametrize("lang,headline", [("vi", "Chào mừng bạn đến với LexiLingo"), ("ja", "LexiLingoへようこそ")])
async def test_the_hero_headline_is_text_in_the_learners_language(sent, lang, headline):
    await EmailService.send_welcome_email(to_email=TO, display_name="A", lang=lang)

    assert 'class="ll-hero-title"' in _html(sent.call_args.args[0])
    assert f">{headline}</div>" in _html(sent.call_args.args[0])


@pytest.mark.asyncio
@pytest.mark.parametrize("day,subject", [(1, "Your first LexiLingo lesson takes five minutes"), (3, "Still want to start with LexiLingo?")])
async def test_activation_nudge_links_to_the_start_route_and_shares_the_hero(sent, day, subject):
    assert await EmailService.send_activation_nudge_email(
        to_email=TO, display_name="Minh Anh", user_id=UID, day=day, start_link="https://lexilingo.me/courses"
    ) is True

    message = sent.call_args.args[0]
    html = _html(message)
    assert message["Subject"] == subject
    assert "/email/unsubscribe?token=" in message["List-Unsubscribe"]
    assert 'href="https://lexilingo.me/courses"' in html
    base = settings.EMAIL_ASSET_BASE_URL.rstrip("/")
    assert f"url('{base}/hero.jpg')" in html
    assert not re.findall(r"\{[a-z_]+\}", html)
    assert "https://lexilingo.me/courses" in message.get_body(("plain",)).get_content()


LANGS = ["vi", "en", "es", "fr", "ja", "ko", "zh"]


def _localized_senders(lang):
    return {
        "verification_email": lambda: EmailService.send_verification_email(TO, "t", "Minh Anh", lang),
        "password_reset_email": lambda: EmailService.send_password_reset_email(
            to_email=TO, reset_token="t", display_name="Minh Anh", lang=lang
        ),
        "vocabulary_review_reminder": lambda: EmailService.send_vocabulary_review_reminder_email(
            to_email=TO, display_name="Minh Anh", due_count=12, lang=lang
        ),
        "welcome_email": lambda: EmailService.send_welcome_email(
            to_email=TO, display_name="Minh Anh", lang=lang
        ),
        "password_changed_email": lambda: EmailService.send_password_changed_email(
            to_email=TO, display_name="Minh Anh", lang=lang
        ),
        "weekly_summary_email": lambda: EmailService.send_weekly_summary_email(
            to_email=TO, display_name="Minh Anh", user_id=UID, xp=1280, streak_days=6,
            words_learned=42, suggestion_title="IELTS Foundation",
            suggestion_link="https://lexilingo.me/courses/ielts", lang=lang,
        ),
        "streak_at_risk_email": lambda: EmailService.send_streak_at_risk_email(
            to_email=TO, display_name="Minh Anh", user_id=UID, streak_days=6, lang=lang
        ),
        "activation_d1": lambda: EmailService.send_activation_nudge_email(
            to_email=TO, display_name="Minh Anh", user_id=UID, day=1,
            start_link="https://lexilingo.me/courses", lang=lang,
        ),
        "activation_d3": lambda: EmailService.send_activation_nudge_email(
            to_email=TO, display_name="Minh Anh", user_id=UID, day=3,
            start_link="https://lexilingo.me/courses", lang=lang,
        ),
    }


@pytest.mark.asyncio
@pytest.mark.parametrize("lang", LANGS)
async def test_every_email_renders_completely_in_every_language(sent, lang):
    english = {}
    if lang != "en":
        for name, send in _localized_senders("en").items():
            await send()
            english[name] = sent.call_args.args[0]["Subject"]

    for name, send in _localized_senders(lang).items():
        assert await send() is True, name
        message = sent.call_args.args[0]
        html = _html(message)
        text = message.get_body(("plain",)).get_content()
        for body in (html, text):
            assert not re.findall(r"\{[a-z_]+\}", body), (lang, name)
            assert "[b]" not in body and "[/a]" not in body and "[a:" not in body, (lang, name)
            assert "Minh Anh" in body, (lang, name)
        assert f'<html lang="{lang}">' in html
        if lang != "en":
            assert message["Subject"] != english[name], (lang, name)


@pytest.mark.asyncio
async def test_an_unknown_language_falls_back_to_english(sent):
    await EmailService.send_welcome_email(to_email=TO, display_name="A", lang="de")

    message = sent.call_args.args[0]
    assert message["Subject"] == "Welcome to LexiLingo"
    assert '<html lang="en">' in _html(message)


@pytest.mark.asyncio
async def test_a_vietnamese_reminder_reads_naturally(sent):
    await EmailService.send_streak_at_risk_email(
        to_email=TO, display_name="Linh", user_id=UID, streak_days=6, lang="vi"
    )

    message = sent.call_args.args[0]
    assert message["Subject"] == "Chuỗi 6 ngày của bạn kết thúc tối nay"
    html = _html(message)
    assert 'Chào <strong class="ll-h" style="color:#111418;">Linh</strong>, hôm nay bạn chưa luyện tập.' in html
    assert ">Huỷ đăng ký</a>" in html
    assert "Chào Linh, hôm nay bạn chưa luyện tập." in message.get_body(("plain",)).get_content()
