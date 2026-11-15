from unittest.mock import patch

import pytest

from app.core.config import settings
from app.services.email_service import EmailService, is_undeliverable


@pytest.mark.parametrize(
    "address",
    [
        "preview_home@lexilingo.dev",
        "demo_3@lexilingo.dev",
        "learner@example.com",
        "seed_user@lexilingo.test",
        "someone@printer.local",
        "not-an-address",
        "",
    ],
)
def test_fake_addresses_are_undeliverable(address):
    assert is_undeliverable(address)


@pytest.mark.parametrize(
    "address",
    ["nhthang.dev@gmail.com", "nhthang.dev+test_1@gmail.com", "Minh Anh <a@outlook.com>"],
)
def test_real_addresses_are_deliverable(address):
    assert not is_undeliverable(address)


@pytest.fixture
def smtp(monkeypatch):
    monkeypatch.setattr(settings, "SMTP_HOST", "smtp.test")
    monkeypatch.setattr(settings, "SMTP_USERNAME", "u")
    monkeypatch.setattr(settings, "SMTP_PASSWORD", "p")
    monkeypatch.setattr(settings, "SMTP_USE_SSL", False)
    with patch("app.services.email_service.smtplib.SMTP", autospec=True) as client:
        yield client


@pytest.mark.asyncio
async def test_verification_to_a_fake_address_never_reaches_smtp(smtp):
    sent = await EmailService.send_verification_email(
        to_email="preview_home@lexilingo.dev", token="t", display_name="Minh Anh"
    )

    assert sent is False
    smtp.assert_not_called()


@pytest.mark.asyncio
async def test_verification_to_a_real_address_is_sent(smtp):
    sent = await EmailService.send_verification_email(
        to_email="nhthang.dev@gmail.com", token="t", display_name="Minh Anh"
    )

    assert sent is True
    smtp.assert_called_once()
