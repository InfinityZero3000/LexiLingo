from unittest.mock import patch

import pytest

from app.core.config import settings
from app.services.email_service import EmailService


@pytest.fixture
def sent(monkeypatch):
    monkeypatch.setattr(settings, "SMTP_HOST", "smtp.test")
    monkeypatch.setattr(settings, "SMTP_USERNAME", "u")
    monkeypatch.setattr(settings, "SMTP_PASSWORD", "p")
    monkeypatch.setattr(settings, "SMTP_USE_SSL", False)
    monkeypatch.setattr(settings, "EMAIL_FROM", "noreply@lexilingo.me")
    monkeypatch.setattr(settings, "EMAIL_FROM_NAME", "LexiLingo")
    with patch("app.services.email_service.smtplib.SMTP", autospec=True) as client:
        yield client.return_value.__enter__.return_value.send_message


@pytest.mark.asyncio
async def test_sender_has_a_display_name_on_the_project_domain(sent, monkeypatch):
    monkeypatch.setattr(settings, "EMAIL_REPLY_TO", None)

    await EmailService.send_verification_email(
        to_email="nhthang.dev@gmail.com", token="t", display_name="Minh Anh"
    )

    message = sent.call_args.args[0]
    assert message["From"] == "LexiLingo <noreply@lexilingo.me>"
    assert message["Reply-To"] is None


@pytest.mark.asyncio
async def test_reply_to_is_set_only_when_configured(sent, monkeypatch):
    monkeypatch.setattr(settings, "EMAIL_REPLY_TO", "support@lexilingo.me")

    await EmailService.send_verification_email(
        to_email="nhthang.dev@gmail.com", token="t", display_name="Minh Anh"
    )

    assert sent.call_args.args[0]["Reply-To"] == "support@lexilingo.me"


@pytest.mark.asyncio
async def test_reminder_offers_an_unsubscribe_link(sent):
    await EmailService.send_vocabulary_review_reminder_email(
        to_email="nhthang.dev@gmail.com", display_name="Minh Anh", due_count=3
    )

    unsubscribe = sent.call_args.args[0]["List-Unsubscribe"]
    assert unsubscribe.startswith("<https://") and unsubscribe.endswith("/settings>")
