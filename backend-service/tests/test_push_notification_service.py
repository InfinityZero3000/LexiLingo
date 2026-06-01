import pytest

from app.services.push_notification_service import PushNotificationService


@pytest.mark.asyncio
async def test_send_review_reminder_returns_false_without_tokens():
    sent = await PushNotificationService().send_review_reminder(
        tokens=[],
        due_count=3,
        title="Review",
        body="Review words",
    )

    assert sent is False


@pytest.mark.asyncio
async def test_send_review_reminder_returns_false_when_firebase_missing(monkeypatch):
    from app.services import push_notification_service as module

    def raise_missing():
        raise RuntimeError("missing firebase")

    monkeypatch.setattr(module, "_init_firebase_app", raise_missing)

    sent = await PushNotificationService().send_review_reminder(
        tokens=["token"],
        due_count=3,
        title="Review",
        body="Review words",
    )

    assert sent is False
