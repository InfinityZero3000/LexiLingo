"""Operator read-outs: reminders, product usage and content-agent health.

Everything here is derived from rows the app already writes; it only makes them
visible. Integration health and API quotas keep their own routes
(`/health/integrations`, `/admin/quota-usage`).
"""
import asyncio
import json
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.celery_app import celery_app
from app.core.celery_status import LAST_RUN_KEY, build_task_report
from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import require_permission
from app.core.redis import RedisClient
from app.services.backup_status import read_backup_status
from app.models.content_agent import ContentAgentJob
from app.models.product_event import ProductEvent
from app.models.reminder import ReminderDelivery
from app.models.user import User

router = APIRouter(prefix="/admin/ops", tags=["Admin - Operations"])


def _since(days: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=days)


def _day(value) -> str:
    return value if isinstance(value, str) else value.isoformat()


@router.get("/reminders")
async def reminder_overview(
    days: int = Query(14, ge=1, le=90),
    admin: User = Depends(require_permission("ops:read")),
    db: AsyncSession = Depends(get_db),
):
    """Reminder deliveries by status, channel and day, plus whether the feature is switched on."""
    since = _since(days)
    day = func.date(ReminderDelivery.scheduled_for)

    per_day = (
        await db.execute(
            select(day, ReminderDelivery.status, func.count())
            .where(ReminderDelivery.scheduled_for >= since)
            .group_by(day, ReminderDelivery.status)
            .order_by(day)
        )
    ).all()
    per_channel = (
        await db.execute(
            select(ReminderDelivery.channel, ReminderDelivery.status, func.count())
            .where(ReminderDelivery.scheduled_for >= since)
            .group_by(ReminderDelivery.channel, ReminderDelivery.status)
        )
    ).all()

    by_day: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    totals: dict[str, int] = defaultdict(int)
    for date_value, status_value, count in per_day:
        by_day[_day(date_value)][status_value] += count
        totals[status_value] += count

    return {
        "days": days,
        "enabled": settings.REMINDERS_ENABLED,
        "dry_run": settings.REMINDER_DRY_RUN,
        "totals": dict(totals),
        "by_day": [{"date": d, **dict(counts)} for d, counts in sorted(by_day.items())],
        "by_channel": [
            {"channel": channel, "status": status_value, "count": count}
            for channel, status_value, count in per_channel
        ],
    }


@router.get("/product-events")
async def product_event_overview(
    days: int = Query(14, ge=1, le=90),
    limit: int = Query(20, ge=1, le=100),
    admin: User = Depends(require_permission("ops:read")),
    db: AsyncSession = Depends(get_db),
):
    """Most frequent product events and the daily volume."""
    since = _since(days)
    day = func.date(ProductEvent.created_at)

    top = (
        await db.execute(
            select(ProductEvent.event_name, func.count().label("n"), func.max(ProductEvent.created_at))
            .where(ProductEvent.created_at >= since)
            .group_by(ProductEvent.event_name)
            .order_by(func.count().desc())
            .limit(limit)
        )
    ).all()
    per_day = (
        await db.execute(
            select(day, func.count())
            .where(ProductEvent.created_at >= since)
            .group_by(day)
            .order_by(day)
        )
    ).all()

    return {
        "days": days,
        "total": sum(count for _, count in per_day),
        "events": [
            {
                "event_name": name,
                "count": count,
                "last_at": last.isoformat() if last else None,
            }
            for name, count, last in top
        ],
        "by_day": [{"date": _day(d), "count": count} for d, count in per_day],
    }


@router.get("/content-agent")
async def content_agent_overview(
    admin: User = Depends(require_permission("ops:read")),
    db: AsyncSession = Depends(get_db),
):
    """Content-agent jobs by status and the most recent errors."""
    counts = (
        await db.execute(select(ContentAgentJob.status, func.count()).group_by(ContentAgentJob.status))
    ).all()
    failures = (
        (
            await db.execute(
                select(ContentAgentJob)
                .where(ContentAgentJob.error_message.is_not(None))
                .order_by(ContentAgentJob.updated_at.desc())
                .limit(5)
            )
        )
        .scalars()
        .all()
    )
    return {
        "by_status": {status_value: count for status_value, count in counts},
        "recent_failures": [
            {
                "id": str(job.id),
                "status": job.status,
                "error": (job.error_message or "")[:300],
                "updated_at": job.updated_at.isoformat() if job.updated_at else None,
            }
            for job in failures
        ],
    }


def _ping_workers() -> list[str] | None:
    """Names of workers that answered within a second; None when Celery cannot be asked."""
    control = getattr(celery_app, "control", None)
    if control is None:
        return None
    try:
        replies = control.inspect(timeout=1).ping() or {}
    except Exception:
        return None
    return sorted(replies)


@router.get("/celery")
async def celery_overview(admin: User = Depends(require_permission("ops:read"))):
    """Is the worker answering, is beat ticking, and when did each scheduled task last run."""
    workers = await asyncio.to_thread(_ping_workers)

    entries: dict[str, dict] = {}
    queue_depth = None
    client = await RedisClient.get_instance()
    if client is not None:
        try:
            raw = await client.hgetall(LAST_RUN_KEY)
            entries = {
                (k.decode() if isinstance(k, bytes) else k): json.loads(v)
                for k, v in raw.items()
            }
            if settings.effective_celery_broker_url == settings.REDIS_URL:
                queue_depth = int(await client.llen("celery"))
        except Exception:
            entries = {}

    report = build_task_report(entries, celery_app.conf.beat_schedule, datetime.now(timezone.utc))
    return {
        "worker": {"reachable": workers is not None, "online": bool(workers), "nodes": workers or []},
        "beat_alive": report["beat_alive"],
        "queue_depth": queue_depth,
        "reminders_enabled": settings.REMINDERS_ENABLED,
        "tasks": report["tasks"],
    }


@router.get("/backups")
async def backup_overview(admin: User = Depends(require_permission("ops:read"))):
    """Newest backup, last restore test and whether an unrecovered failure alert is outstanding."""
    return await asyncio.to_thread(read_backup_status, settings.BACKUP_STATE_DIR)
