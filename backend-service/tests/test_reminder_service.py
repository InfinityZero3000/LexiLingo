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


# --- timezone validation -----------------------------------------------------

import pytest
from pydantic import ValidationError

from app.schemas.reminders import ReminderPreferenceUpdate


@pytest.mark.parametrize("alias", ["Asia/Saigon", "Asia/Calcutta", "Europe/Kiev"])
def test_legacy_timezone_aliases_browsers_still_report_are_accepted(alias):
    # Chrome on macOS reports Asia/Saigon; python:slim ships no alias table,
    # so without the tzdata package the whole preferences update was a 422.
    assert ReminderPreferenceUpdate(timezone=alias).timezone == alias


def test_tzdata_ships_with_the_app_not_just_the_os():
    # CI runners and dev machines have a system zoneinfo, the slim prod image
    # does not, so the alias test above cannot fail there. Guard the dependency.
    import importlib.util

    assert importlib.util.find_spec("tzdata") is not None


def test_timezone_must_be_an_iana_name():
    assert ReminderPreferenceUpdate(timezone="Europe/Paris").timezone == "Europe/Paris"
    with pytest.raises(ValidationError):
        ReminderPreferenceUpdate(timezone="Mars/Olympus")


# --- scan: stale rows are skipped, one failure does not sink the batch -------

from contextlib import asynccontextmanager
from datetime import timedelta
from types import SimpleNamespace

from app.services.reminder_service import ReminderProcessResult


class _Prefs:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self

    def all(self):
        return self._rows


class _ScanDb:
    def __init__(self, rows):
        self._rows = rows

    async def execute(self, _stmt):
        return _Prefs(self._rows)

    @asynccontextmanager
    async def begin_nested(self):
        yield


def _pref(now, *, late_minutes):
    return SimpleNamespace(
        user_id=uuid4(),
        reminder_time_local="09:00",
        timezone="Asia/Ho_Chi_Minh",
        next_check_at=now - timedelta(minutes=late_minutes),
    )


class _Service(ReminderService):
    def __init__(self, failing):
        super().__init__(fsrs_scheduler=object(), push_service=object())
        self.failing = failing
        self.processed_users = []

    async def process_preference(self, db, *, preference, now_utc):
        if preference.user_id == self.failing:
            raise RuntimeError("boom")
        self.processed_users.append(preference.user_id)
        return ReminderProcessResult(processed=1, sent=1)


async def test_scan_skips_stale_and_isolates_failures(monkeypatch):
    monkeypatch.setattr(settings, "REMINDERS_ENABLED", True)
    monkeypatch.setattr(settings, "REMINDER_MAX_LATENESS_MINUTES", 180)
    now = datetime(2026, 6, 1, 3, 0, tzinfo=timezone.utc)

    stale = _pref(now, late_minutes=600)
    bad = _pref(now, late_minutes=5)
    good = _pref(now, late_minutes=5)
    service = _Service(failing=bad.user_id)

    totals = await service.scan_due_preferences(
        _ScanDb([stale, bad, good]), now_utc=now
    )

    assert totals["processed"] == 3
    assert totals["sent"] == 1
    assert totals["skipped"] == 1
    assert totals["failed"] == 1
    assert service.processed_users == [good.user_id]
    # Stale and failed rows are pushed to the next slot so they do not loop.
    assert stale.next_check_at > now
    assert bad.next_check_at > now
