import pytest

from app.services.email_service import EmailService


def test_review_reminder_templates_render():
    context = {
        "display_name": "Learner",
        "due_count": "5",
        "review_link": "https://lexilingo.me/vocabulary/review",
        "settings_link": "https://lexilingo.me/settings",
        "support_email": "nhthang2077@gmail.com",
    }

    html = EmailService._render_template("vocabulary_review_reminder.html", context)
    text = EmailService._render_template("vocabulary_review_reminder.txt", context)

    assert "Learner" in html
    assert "5" in text
    assert "https://lexilingo.me/vocabulary/review" in text


@pytest.mark.asyncio
async def test_review_reminder_email_returns_false_without_smtp(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "SMTP_HOST", None)

    sent = await EmailService.send_vocabulary_review_reminder_email(
        to_email="learner@example.com",
        display_name="Learner",
        due_count=5,
    )

    assert sent is False
