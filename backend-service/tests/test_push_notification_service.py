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


def _capture_sends(monkeypatch):
    from app.services import push_notification_service as module

    monkeypatch.setattr(module, "_init_firebase_app", lambda: None)
    sent = []

    class Response:
        def __init__(self, n):
            self.success_count = n
            self.failure_count = 0

    def fake_send(message):
        sent.append(message)
        return Response(len(message.tokens))

    monkeypatch.setattr(module.messaging, "send_each_for_multicast", fake_send)
    return sent


@pytest.mark.asyncio
async def test_review_reminder_is_branded_and_grouped(monkeypatch):
    sent = _capture_sends(monkeypatch)

    ok = await PushNotificationService().send_review_reminder(
        tokens=["token"], due_count=3, title="t", body="b"
    )

    assert ok is True
    android = sent[0].android.notification
    assert android.icon == "ic_stat_lexilingo"
    assert android.color == "#137FEC"
    assert android.channel_id == "daily_reminder_channel"
    assert sent[0].apns.payload.aps.thread_id == "vocabulary_review_reminder"


@pytest.mark.asyncio
async def test_more_than_500_tokens_go_out_in_batches(monkeypatch):
    sent = _capture_sends(monkeypatch)

    ok = await PushNotificationService().send_word_of_day(
        tokens=[f"t{i}" for i in range(1201)], word="book", definition="a written work"
    )

    assert ok is True
    assert [len(m.tokens) for m in sent] == [500, 500, 201]
    assert sent[0].notification.title == "✨ Word of the day: book"
