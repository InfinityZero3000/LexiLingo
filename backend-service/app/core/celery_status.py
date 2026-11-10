"""Last-run bookkeeping for Celery tasks, so the admin can see whether the schedule is actually running.

Workers write with a plain sync Redis client from the signal hooks: a task body
runs its own event loop per call, so the async singleton cannot be shared.
Writing is best effort and must never fail a task.
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

from app.core.config import settings

logger = logging.getLogger(__name__)

LAST_RUN_KEY = "lexilingo:celery:last_run"
LAST_RUN_TTL_SECONDS = 14 * 24 * 3600
BEAT_HEARTBEAT_TASK = "app.tasks.event_worker.drain_content_interaction_stream"

_sync_client: Any = None


def _client() -> Any:
    global _sync_client
    if _sync_client is None:
        import redis

        _sync_client = redis.Redis.from_url(
            settings.effective_celery_result_backend or settings.REDIS_URL,
            socket_connect_timeout=2,
            socket_timeout=2,
        )
    return _sync_client


def record_run(task_name: str | None, state: str, runtime: float | None = None, error: str | None = None) -> None:
    if not task_name:
        return
    entry = {
        "state": state,
        "at": datetime.now(timezone.utc).isoformat(),
        "runtime": round(runtime, 3) if runtime is not None else None,
        "error": (error or "")[:300] or None,
    }
    try:
        client = _client()
        client.hset(LAST_RUN_KEY, task_name, json.dumps(entry))
        client.expire(LAST_RUN_KEY, LAST_RUN_TTL_SECONDS)
    except Exception as exc:  # noqa: BLE001 - observability must not break the task
        logger.debug("Could not record celery run for %s: %s", task_name, exc)


def max_age_seconds(schedule: Any) -> int:
    """How old a success may get before the schedule counts as stalled."""
    if isinstance(schedule, (int, float)):
        return max(int(schedule) * 3, 120)
    hours = getattr(schedule, "hour", None)
    days = getattr(schedule, "day_of_week", None)
    if days is not None and len(days) < 7:
        return 8 * 24 * 3600
    period_hours = 24 / max(len(hours), 1) if hours else 1
    return int(period_hours * 3600 * 1.5 + 3600)


def schedule_label(schedule: Any) -> str:
    if isinstance(schedule, (int, float)):
        return f"every {int(schedule)}s"
    return str(getattr(schedule, "human_readable", None) or schedule)


def task_status(entry: dict | None, schedule: Any, now: datetime) -> str:
    if not entry:
        return "never"
    if entry.get("state") == "FAILURE":
        return "failed"
    try:
        age = (now - datetime.fromisoformat(entry["at"])).total_seconds()
    except (KeyError, ValueError):
        return "never"
    return "ok" if age <= max_age_seconds(schedule) else "stale"


def build_task_report(entries: dict[str, dict], beat_schedule: dict[str, dict], now: datetime) -> dict:
    """One row per scheduled task plus whether beat looks alive (its 10s heartbeat task keeps running)."""
    tasks = []
    for name, spec in beat_schedule.items():
        task = spec["task"]
        entry = entries.get(task)
        tasks.append(
            {
                "name": name,
                "task": task,
                "schedule": schedule_label(spec["schedule"]),
                "status": task_status(entry, spec["schedule"], now),
                "last_run_at": entry.get("at") if entry else None,
                "last_state": entry.get("state") if entry else None,
                "runtime": entry.get("runtime") if entry else None,
                "error": entry.get("error") if entry else None,
            }
        )
    beat_entry = entries.get(BEAT_HEARTBEAT_TASK)
    beat_alive = False
    if beat_entry:
        try:
            beat_alive = (now - datetime.fromisoformat(beat_entry["at"])).total_seconds() <= 120
        except (KeyError, ValueError):
            beat_alive = False
    return {"tasks": tasks, "beat_alive": beat_alive}


def healthcheck_beat(max_age: int = 120) -> None:
    """Container healthcheck: exit 0 only while the 10s heartbeat task keeps being recorded."""
    import sys

    try:
        raw = _client().hget(LAST_RUN_KEY, BEAT_HEARTBEAT_TASK)
        at = datetime.fromisoformat(json.loads(raw)["at"])
        ok = (datetime.now(timezone.utc) - at).total_seconds() <= max_age
    except Exception:  # noqa: BLE001
        ok = False
    sys.exit(0 if ok else 1)
