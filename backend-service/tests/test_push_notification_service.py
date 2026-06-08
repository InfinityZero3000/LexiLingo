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


@pytest.mark.asyncio
async def test_send_starter_reward_builds_expected_payload(monkeypatch):
    from app.services import push_notification_service as module

    monkeypatch.setattr(module, "_init_firebase_app", lambda: None)

    captured = {}

    class Response:
        success_count = 1

    def fake_send(message):
        captured["message"] = message
        return Response()

    monkeypatch.setattr(module.messaging, "send_each_for_multicast", fake_send)

    sent = await PushNotificationService().send_starter_reward(
        tokens=["token"],
        gems=100,
        reward_key="new_user_starter_gems_v1",
        title="Welcome gift",
        body="100 Gems are waiting.",
    )

    assert sent is True
    assert captured["message"].data["type"] == "starter_reward"
    assert captured["message"].data["gems"] == "100"
