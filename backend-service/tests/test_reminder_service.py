from datetime import datetime, timezone
from uuid import uuid4

from app.core.config import settings
from app.models.reminder import ReminderDelivery, UserReminderPreference
from app.services.reminder_service import ReminderService


def test_reminder_models_have_expected_tables():
    assert UserReminderPreference.__tablename__ == "user_reminder_preferences"
    assert ReminderDelivery.__tablename__ == "reminder_deliveries"


def test_reminder_settings_exist_and_are_valid_types():
    assert isinstance(settings.REMINDERS_ENABLED, bool)
    assert isinstance(settings.REMINDER_DRY_RUN, bool)
    assert settings.REMINDER_DEFAULT_TIMEZONE == "Asia/Ho_Chi_Minh"
    assert settings.REMINDER_SCAN_BATCH_SIZE >= 1
    assert settings.REMINDER_SCAN_INTERVAL_SECONDS > 0


def test_celery_has_reminder_schedule():
    from app.core.celery_app import celery_app

    assert "scan-fsrs-reminders" in celery_app.conf.beat_schedule


def test_build_dedupe_key_is_channel_and_date_scoped():
    user_id = uuid4()
    service = ReminderService()

    key = service.build_dedupe_key(
        user_id=user_id,
        channel="push",
        local_date="2026-06-01",
    )

    assert key == f"vocabulary_review:{user_id}:2026-06-01:push"


def test_compute_next_check_at_moves_past_time_to_next_day():
    service = ReminderService()
    now = datetime(2026, 6, 1, 3, 0, tzinfo=timezone.utc)  # 10:00 VN time

    next_check = service.compute_next_check_at(
        reminder_time_local="09:00",
        timezone_name="Asia/Ho_Chi_Minh",
        now_utc=now,
    )

    assert next_check > now
    assert next_check.astimezone(timezone.utc).date().isoformat() == "2026-06-02"
