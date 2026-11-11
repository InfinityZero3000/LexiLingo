"""Operator read-outs aggregate the rows the app already writes (real SQL, in-memory SQLite)."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings
from app.core.database import Base
from app.models.content_agent import ContentAgentJob
from app.models.product_event import ProductEvent
from app.models.reminder import ReminderDelivery
from app.routes import admin_ops

NOW = datetime.now(timezone.utc)


@pytest_asyncio.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(
            lambda c: Base.metadata.create_all(
                c,
                tables=[ReminderDelivery.__table__, ProductEvent.__table__, ContentAgentJob.__table__],
            )
        )
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        yield session
    await engine.dispose()


def _delivery(status, channel="push", days_ago=0):
    return ReminderDelivery(
        user_id=uuid4(), channel=channel, status=status, due_count=3,
        dedupe_key=str(uuid4()), scheduled_for=NOW - timedelta(days=days_ago),
    )


def _event(name, days_ago=0):
    return ProductEvent(
        event_id=uuid4(), user_id=uuid4(), event_name=name, properties={}, source="app",
        client_timestamp=NOW, created_at=NOW - timedelta(days=days_ago),
    )


@pytest.mark.asyncio
async def test_reminder_overview_counts_by_status_channel_and_flags(db, monkeypatch):
    monkeypatch.setattr(settings, "REMINDERS_ENABLED", True)
    monkeypatch.setattr(settings, "REMINDER_DRY_RUN", True)
    db.add_all([
        _delivery("sent"), _delivery("sent"), _delivery("failed", "email"),
        _delivery("sent", days_ago=40),  # outside the window
    ])
    await db.commit()

    data = await admin_ops.reminder_overview(14, SimpleNamespace(), db)

    assert data["enabled"] is True and data["dry_run"] is True
    assert data["totals"] == {"sent": 2, "failed": 1}
    assert {(r["channel"], r["status"]): r["count"] for r in data["by_channel"]} == {
        ("push", "sent"): 2, ("email", "failed"): 1,
    }
    assert data["by_day"][0]["sent"] == 2 and data["by_day"][0]["failed"] == 1


@pytest.mark.asyncio
async def test_product_events_rank_by_frequency_and_respect_the_window(db):
    db.add_all([_event("lesson_start"), _event("lesson_start"), _event("review_done"),
                _event("lesson_start", days_ago=60)])
    await db.commit()

    data = await admin_ops.product_event_overview(14, 20, SimpleNamespace(), db)

    assert data["total"] == 3
    assert [(e["event_name"], e["count"]) for e in data["events"]] == [("lesson_start", 2), ("review_done", 1)]
    assert sum(d["count"] for d in data["by_day"]) == 3


@pytest.mark.asyncio
async def test_content_agent_overview_is_empty_without_jobs(db):
    data = await admin_ops.content_agent_overview(SimpleNamespace(), db)

    assert data == {"by_status": {}, "recent_failures": []}


# --- quota reset: a cost-protection limit, so super admin only and audited ---

from unittest.mock import AsyncMock, patch

from app.core.dependencies import get_current_super_admin
from app.routes import admin_system


def test_quota_reset_requires_a_super_admin():
    route = next(r for r in admin_system.router.routes if getattr(r, "path", "").endswith("/quota-reset/{api_name}"))
    assert get_current_super_admin in [d.call for d in route.dependant.dependencies]


@pytest.mark.asyncio
async def test_quota_reset_leaves_an_audit_row(db):
    admin = SimpleNamespace(id=uuid4())
    request = SimpleNamespace(state=SimpleNamespace(), client=None, headers={})
    added = []
    db.add = added.append  # capture instead of persisting: audit_logs is not created here

    with patch("app.services.quota_manager.QuotaManager.reset_quota", new=AsyncMock(return_value=True)), patch(
        "app.services.quota_manager.QuotaManager.get_usage", new=AsyncMock(return_value={"api": "newsapi"})
    ):
        await admin_system.reset_quota("newsapi", request, admin, db)

    (audit,) = added
    assert (audit.action, audit.resource_type, audit.resource_id) == ("quota_reset", "quota", "newsapi")
    assert audit.user_id == admin.id


# ── celery ────────────────────────────────────────────────────────────────

def test_task_status_distinguishes_never_ok_stale_and_failed():
    from celery.schedules import crontab

    from app.core.celery_status import task_status

    now = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
    fresh = {"state": "SUCCESS", "at": (now - timedelta(minutes=2)).isoformat()}
    old = {"state": "SUCCESS", "at": (now - timedelta(days=3)).isoformat()}
    daily = crontab(hour=3, minute=0)

    assert task_status(None, 300, now) == "never"
    assert task_status(fresh, 300, now) == "ok"
    assert task_status({**fresh, "state": "FAILURE"}, 300, now) == "failed"
    assert task_status(old, daily, now) == "stale"
    assert task_status(old, crontab(hour=3, minute=0, day_of_week=1), now) == "ok"


def test_report_says_beat_is_alive_only_while_its_heartbeat_task_keeps_running():
    from app.core.celery_status import BEAT_HEARTBEAT_TASK, build_task_report

    now = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
    schedule = {"drain": {"task": BEAT_HEARTBEAT_TASK, "schedule": 10}}

    live = build_task_report({BEAT_HEARTBEAT_TASK: {"state": "SUCCESS", "at": (now - timedelta(seconds=15)).isoformat()}}, schedule, now)
    dead = build_task_report({BEAT_HEARTBEAT_TASK: {"state": "SUCCESS", "at": (now - timedelta(minutes=10)).isoformat()}}, schedule, now)

    assert live["beat_alive"] is True and live["tasks"][0]["status"] == "ok"
    assert dead["beat_alive"] is False and dead["tasks"][0]["status"] == "stale"


def test_recording_a_run_never_raises_even_with_redis_down(monkeypatch):
    from app.core import celery_status

    class Broken:
        def hset(self, *a, **k):
            raise ConnectionError("redis down")

    monkeypatch.setattr(celery_status, "_client", lambda: Broken())
    celery_status.record_run("app.tasks.x", "SUCCESS", 0.1)  # must not raise


@pytest.mark.asyncio
async def test_celery_overview_reports_an_unreachable_worker_instead_of_failing(monkeypatch):
    monkeypatch.setattr(admin_ops, "_ping_workers", lambda: None)
    result = await admin_ops.celery_overview(admin=SimpleNamespace())

    assert result["worker"] == {"reachable": False, "online": False, "nodes": []}
    assert {t["status"] for t in result["tasks"]} <= {"never", "ok", "stale", "failed"}


@pytest.mark.parametrize("age_seconds,exit_code", [(20, 0), (900, 1)])
def test_beat_healthcheck_exits_nonzero_when_the_heartbeat_is_stale(monkeypatch, age_seconds, exit_code):
    import json

    from app.core import celery_status

    at = (datetime.now(timezone.utc) - timedelta(seconds=age_seconds)).isoformat()

    class Fake:
        def hget(self, *_):
            return json.dumps({"state": "SUCCESS", "at": at})

    monkeypatch.setattr(celery_status, "_client", lambda: Fake())
    with pytest.raises(SystemExit) as exit_:
        celery_status.healthcheck_beat()
    assert exit_.value.code == exit_code


# ── backups ───────────────────────────────────────────────────────────────

def _state_dir(tmp_path, backup=None, verify=None, marker=None):
    import json

    if backup is not None:
        (tmp_path / "backup-last.json").write_text(json.dumps(backup))
    if verify is not None:
        (tmp_path / "verify-last.json").write_text(json.dumps(verify))
    if marker:
        (tmp_path / "backup-failure.state").write_text(f"failed_unit=x\ntimestamp_utc={marker}\nhost=h\n")
    return tmp_path


def test_backup_status_is_unavailable_when_the_state_directory_is_not_mounted(tmp_path):
    from app.services.backup_status import read_backup_status

    assert read_backup_status(tmp_path / "nope")["state"] == "unavailable"


def test_backup_status_grades_age_and_the_verify_result(tmp_path):
    from app.services.backup_status import read_backup_status

    now = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
    iso = lambda **kw: (now - timedelta(**kw)).strftime("%Y-%m-%dT%H:%M:%SZ")

    fresh = read_backup_status(_state_dir(tmp_path, {"result": "ok", "at": iso(hours=2)}, {"result": "ok", "at": iso(days=2)}), now)
    assert fresh["state"] == "ok" and fresh["verify"]["state"] == "ok"

    stale = read_backup_status(_state_dir(tmp_path, {"result": "ok", "at": iso(hours=20)}, {"result": "failed", "at": iso(days=1)}), now)
    assert stale["state"] == "stale" and stale["verify"]["state"] == "failed"


def test_an_old_failure_marker_stops_counting_once_a_newer_backup_succeeded(tmp_path):
    from app.services.backup_status import read_backup_status

    now = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
    recovered = _state_dir(tmp_path, {"result": "ok", "at": "2026-11-10T11:00:00Z"}, None, "2026-11-10T05:00:00Z")
    assert read_backup_status(recovered, now)["failure_marker_at"] is None

    outstanding = _state_dir(tmp_path, {"result": "ok", "at": "2026-11-10T04:00:00Z"}, None, "2026-11-10T05:00:00Z")
    assert read_backup_status(outstanding, now)["failure_marker_at"] is not None


def test_a_failed_backup_and_a_missing_one_are_reported_distinctly(tmp_path):
    from app.services.backup_status import read_backup_status

    now = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
    assert read_backup_status(tmp_path, now)["state"] == "never"
    failed = read_backup_status(_state_dir(tmp_path, {"result": "failed", "at": "2026-11-10T11:00:00Z", "error": "exit 1"}), now)
    assert failed["state"] == "failed" and failed["backup"]["error"] == "exit 1"
