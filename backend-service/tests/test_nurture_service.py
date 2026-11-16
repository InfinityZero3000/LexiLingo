from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.models.games import XPTransaction
from app.models.notification import Notification
from app.models.progress import DailyActivity, LessonCompletion, Streak
from app.models.reminder import UserReminderPreference
from app.models.user import User, UserDevice
from app.services import nurture_service as nurture
from app.services.email_service import EmailService
from app.services.push_notification_service import PushNotificationService

# 13:30 UTC is 20:30 in Asia/Ho_Chi_Minh, the default reminder timezone.
NOW = datetime(2026, 11, 16, 13, 30, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def _no_delay(monkeypatch):
    monkeypatch.setattr(settings, "NURTURE_SEND_DELAY_SECONDS", 0)
    monkeypatch.setattr(settings, "NURTURE_STREAK_LOCAL_HOUR", 20)


@pytest.fixture
def live(monkeypatch):
    monkeypatch.setattr(settings, "NURTURE_EMAILS_ENABLED", True)


@pytest.fixture
def senders():
    with (
        patch.object(EmailService, "send_activation_nudge_email", autospec=True, return_value=True) as activation,
        patch.object(EmailService, "send_streak_at_risk_email", autospec=True, return_value=True) as streak,
        patch.object(EmailService, "send_weekly_summary_email", autospec=True, return_value=True) as weekly,
        patch.object(PushNotificationService, "send_nurture", autospec=True, return_value=True) as push,
    ):
        yield type("S", (), {"activation": activation, "streak": streak, "weekly": weekly, "push": push})


async def make_user(db, name, *, email=None, age_hours=30, verified=True, active=True) -> User:
    user = User(
        email=email or f"{name}@gmail.com",
        username=name,
        hashed_password="x",
        display_name=name,
        is_active=active,
        is_verified=verified,
        created_at=NOW - timedelta(hours=age_hours),
    )
    db.add(user)
    await db.commit()
    return user


async def count_rows(db, kind=None) -> int:
    query = select(func.count()).select_from(Notification)
    if kind:
        query = query.where(Notification.type == kind)
    return await db.scalar(query)


@pytest.mark.asyncio
async def test_activation_selects_only_real_verified_unactivated_learners_in_the_window(
    db_session, test_lesson
):
    want = await make_user(db_session, "want", age_hours=30)
    await make_user(db_session, "toonew", age_hours=10)
    await make_user(db_session, "unverified", verified=False)
    await make_user(db_session, "inactive", active=False)
    await make_user(db_session, "seedtest", email="seed1@lexilingo.test")
    await make_user(db_session, "seeddev", email="seed2@lexilingo.dev")
    await make_user(db_session, "reserved", email="someone@example.com")
    optout = await make_user(db_session, "optout")
    db_session.add(UserReminderPreference(user_id=optout.id, nurture_emails_enabled=False))
    learned = await make_user(db_session, "learned")
    db_session.add(LessonCompletion(user_id=learned.id, lesson_id=test_lesson.id, is_passed=True))
    d3 = await make_user(db_session, "d3user", age_hours=80)
    await db_session.commit()

    d1_ids = {r.user_id for r in await nurture.select_activation(db_session, nurture.D1, NOW)}
    d3_ids = {r.user_id for r in await nurture.select_activation(db_session, nurture.D3, NOW)}

    assert d1_ids == {want.id}
    assert d3_ids == {d3.id}


@pytest.mark.asyncio
async def test_two_runs_send_once_and_leave_one_inbox_row(db_session, live, senders):
    user = await make_user(db_session, "once")

    first = await nurture.run_activation(db_session, nurture.D1, NOW)
    second = await nurture.run_activation(db_session, nurture.D1, NOW)

    assert first["sent"] == 1 and second["selected"] == 0
    senders.activation.assert_called_once()
    assert senders.activation.call_args.kwargs["day"] == 1
    row = (await db_session.execute(select(Notification).where(Notification.user_id == user.id))).scalar_one()
    assert (row.type, row.dedupe_key) == ("nurture_d1", "nurture_d1")


@pytest.mark.asyncio
async def test_a_failed_send_gives_the_claim_back_so_the_next_run_retries(db_session, live, senders):
    await make_user(db_session, "retry")
    senders.activation.return_value = False

    failed = await nurture.run_activation(db_session, nurture.D1, NOW)
    assert failed["failed"] == 1
    assert await count_rows(db_session) == 0

    senders.activation.return_value = True
    retried = await nurture.run_activation(db_session, nurture.D1, NOW)
    assert retried["sent"] == 1
    assert await count_rows(db_session) == 1


@pytest.mark.asyncio
async def test_the_database_refuses_a_second_row_for_the_same_user_type_period(db_session):
    user = await make_user(db_session, "unique")

    def row(key):
        return Notification(user_id=user.id, type="nurture_d1", title="t", body="b", dedupe_key=key)

    db_session.add_all([row("nurture_d1"), row(None), row(None)])
    await db_session.commit()
    db_session.add(row("nurture_d1"))
    with pytest.raises(IntegrityError):
        await db_session.commit()


@pytest.mark.asyncio
async def test_concurrent_claim_loses_quietly(db_session):
    user = await make_user(db_session, "race")
    recipient = nurture.Recipient(user.id, user.email, None, "nurture_d1")

    assert await nurture._claim(db_session, recipient, "nurture_d1", "t", "b", "/") is True
    assert await nurture._claim(db_session, recipient, "nurture_d1", "t", "b", "/") is False


@pytest.mark.asyncio
async def test_flag_off_sends_nothing_writes_nothing_and_reports_counts(db_session, senders, monkeypatch):
    assert settings.NURTURE_EMAILS_ENABLED is False
    await make_user(db_session, "dry")
    risk = await make_user(db_session, "risky")
    db_session.add(Streak(user_id=risk.id, current_streak=4, last_activity_date=date(2026, 11, 15)))
    active = await make_user(db_session, "active")
    db_session.add(DailyActivity(user_id=active.id, activity_date=date(2026, 11, 15), xp_earned=10))
    await db_session.commit()

    results = [
        await nurture.run_activation(db_session, nurture.D1, NOW),
        await nurture.run_streak_risk(db_session, NOW),
        await nurture.run_weekly(db_session, NOW),
    ]

    assert [r["mode"] for r in results] == ["dry_run"] * 3
    assert [r["would_send"] for r in results] == [3, 1, 1]
    for sender in (senders.activation, senders.streak, senders.weekly, senders.push):
        sender.assert_not_called()
    assert await count_rows(db_session) == 0


@pytest.mark.asyncio
async def test_activation_pushes_only_to_learners_with_a_device(db_session, live, senders):
    with_device = await make_user(db_session, "withdevice")
    await make_user(db_session, "nodevice")
    db_session.add(UserDevice(user_id=with_device.id, device_id="d-1", fcm_token="tok", device_type="android"))
    await db_session.commit()

    result = await nurture.run_activation(db_session, nurture.D1, NOW)

    assert result["sent"] == 2
    assert senders.activation.call_count == 2
    senders.push.assert_called_once()
    assert senders.push.call_args.kwargs["tokens"] == ["tok"]
    assert senders.push.call_args.kwargs["route"] == settings.NURTURE_START_ROUTE


@pytest.mark.asyncio
async def test_a_push_alone_counts_as_delivered(db_session, live, senders):
    user = await make_user(db_session, "pushonly")
    db_session.add(UserDevice(user_id=user.id, device_id="d-2", fcm_token="tok", device_type="ios"))
    await db_session.commit()
    senders.activation.return_value = False

    assert (await nurture.run_activation(db_session, nurture.D1, NOW))["sent"] == 1
    assert await count_rows(db_session) == 1


async def _streaker(db, name, *, last=date(2026, 11, 15), streak=5, tz=None, **kw) -> User:
    user = await make_user(db, name, **kw)
    db.add(Streak(user_id=user.id, current_streak=streak, last_activity_date=last))
    if tz:
        db.add(UserReminderPreference(user_id=user.id, timezone=tz))
    await db.commit()
    return user


@pytest.mark.asyncio
async def test_streak_risk_picks_the_right_users(db_session):
    want = await _streaker(db_session, "want")
    await _streaker(db_session, "practised_today", last=date(2026, 11, 16))
    await _streaker(db_session, "streak_gone", last=date(2026, 11, 13))
    await _streaker(db_session, "no_streak", streak=0)
    await _streaker(db_session, "unverified", verified=False)
    await _streaker(db_session, "seed", email="s@lexilingo.test")
    optout = await _streaker(db_session, "optout", tz="Asia/Ho_Chi_Minh")
    (await db_session.get(UserReminderPreference, optout.id)).nurture_emails_enabled = False
    pushy = await _streaker(db_session, "pushy")
    db_session.add(UserDevice(user_id=pushy.id, device_id="d-3", fcm_token="tok", device_type="android"))
    xp = await _streaker(db_session, "xp_today")
    db_session.add(
        XPTransaction(
            user_id=xp.id, amount=5, base_amount=5, source="game",
            created_at=NOW - timedelta(hours=2),
        )
    )
    await db_session.commit()

    chosen = await nurture.select_streak_risk(db_session, NOW)

    assert [r.user_id for r in chosen] == [want.id]
    assert chosen[0].period == "2026-11-16"
    assert chosen[0].streak_days == 5


@pytest.mark.asyncio
async def test_streak_risk_waits_for_the_learners_own_evening(db_session):
    ict = await _streaker(db_session, "ict")
    ny = await _streaker(db_session, "ny", tz="America/New_York", last=date(2026, 11, 15))
    bad_tz = await _streaker(db_session, "badtz", tz="Not/AZone")

    at_1330 = {r.user_id for r in await nurture.select_streak_risk(db_session, NOW)}
    # 01:30 UTC next day is 20:30 in New York (UTC-5 in November).
    ny_evening = datetime(2026, 11, 17, 1, 30, tzinfo=timezone.utc)
    ny_row = await db_session.get(Streak, (await db_session.scalar(select(Streak.id).where(Streak.user_id == ny.id))))
    ny_row.last_activity_date = date(2026, 11, 15)
    await db_session.commit()
    at_0130 = {r.user_id for r in await nurture.select_streak_risk(db_session, ny_evening)}

    assert at_1330 == {ict.id, bad_tz.id}, "an unknown zone falls back to the default zone"
    assert at_0130 == {ny.id}
    assert not await nurture.select_streak_risk(db_session, NOW - timedelta(hours=1))


@pytest.mark.asyncio
async def test_streak_risk_is_sent_once_per_local_day(db_session, live, senders):
    await _streaker(db_session, "daily")

    await nurture.run_streak_risk(db_session, NOW)
    await nurture.run_streak_risk(db_session, NOW + timedelta(minutes=20))

    senders.streak.assert_called_once()
    assert senders.streak.call_args.kwargs["streak_days"] == 5
    assert await count_rows(db_session, nurture.STREAK_RISK) == 1


@pytest.mark.asyncio
async def test_weekly_covers_the_last_fourteen_days_and_sends_once_per_iso_week(db_session, live, senders):
    recent = await make_user(db_session, "recent")
    db_session.add_all(
        [
            DailyActivity(user_id=recent.id, activity_date=date(2026, 11, 14), xp_earned=100, vocabulary_reviewed=7),
            DailyActivity(user_id=recent.id, activity_date=date(2026, 11, 15), xp_earned=50, vocabulary_reviewed=3),
        ]
    )
    db_session.add(Streak(user_id=recent.id, current_streak=2, last_activity_date=date(2026, 11, 15)))
    stale = await make_user(db_session, "stale")
    db_session.add(DailyActivity(user_id=stale.id, activity_date=date(2026, 10, 20), xp_earned=10))
    await make_user(db_session, "never")
    await db_session.commit()

    await nurture.run_weekly(db_session, NOW)
    await nurture.run_weekly(db_session, NOW + timedelta(days=2))

    senders.weekly.assert_called_once()
    kwargs = senders.weekly.call_args.kwargs
    assert (kwargs["xp"], kwargs["words_learned"], kwargs["streak_days"]) == (150, 10, 2)
    row = (await db_session.execute(select(Notification).where(Notification.type == "weekly_summary"))).scalar_one()
    assert row.dedupe_key == "2026-W47"

    await nurture.run_weekly(db_session, NOW + timedelta(days=7))
    assert senders.weekly.call_count == 2


@pytest.mark.asyncio
async def test_a_run_never_sends_more_than_the_cap(db_session, live, senders, monkeypatch):
    monkeypatch.setattr(settings, "NURTURE_MAX_PER_RUN", 2)
    for n in range(3):
        await make_user(db_session, f"cap{n}")

    result = await nurture.run_activation(db_session, nurture.D1, NOW)

    assert (result["sent"], result["deferred"]) == (2, 1)


@pytest.mark.asyncio
async def test_opt_out_is_stored_through_the_reminder_preferences_api(async_client, auth_headers):
    response = await async_client.put(
        "/api/v1/users/me/reminder-preferences",
        json={"nurture_emails_enabled": False},
        headers=auth_headers,
    )

    assert response.status_code == 200
    assert response.json()["data"]["nurture_emails_enabled"] is False


def test_beat_schedules_the_three_tasks():
    from app.core.celery_app import celery_app

    tasks = {entry["task"] for entry in celery_app.conf.beat_schedule.values()}
    assert {
        "app.tasks.nurture.send_activation_nudges",
        "app.tasks.nurture.send_streak_risk_emails",
        "app.tasks.nurture.send_weekly_summaries",
    } <= tasks
