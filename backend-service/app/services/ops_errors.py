"""Error monitoring: capture into Redis, flush into grouped rows, alert on spikes, mail digests.

Capture never touches the database: when requests are failing in bulk the
database is often the thing that is broken, and the hot path must stay cheap.
"""
from __future__ import annotations

import asyncio
import hashlib
import html
import json
import logging
import os
import re
import time
import traceback
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from fastapi import Request
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import case, delete, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.redis import RedisClient
from app.models.app_setting import AppSetting
from app.models.ops_error import OpsErrorCount, OpsErrorGroup

logger = logging.getLogger(__name__)

BUF_KEY = "ops:err:buf"
FLUSHING_KEY = "ops:err:buf:flushing"
META_KEY = "ops:err:meta:{fp}"
WINDOW_KEY = "ops:err:win:{fp}:{minute}"
ALERTED_KEY = "ops:err:alerted:{fp}"
FLUSH_LOCK_KEY = "ops:err:lock:flush"
DIGEST_LOCK_KEY = "ops:err:lock:digest"

META_TTL_SECONDS = 86400
WINDOW_TTL_SECONDS = 900
SPIKE_WINDOW_MINUTES = 5
REDIS_TIMEOUT_SECONDS = 0.3
MAX_ROWS_PER_SERVICE = 15
RETENTION_DAYS = 30

SETTINGS_KEY = "ops.error_report"
LAST_DIGEST_KEY = "ops.error_report.last_digest_at"
DIGEST_INTERVALS = (15, 30, 60, 180, 360, 720, 1440)
MAX_RECIPIENTS = 10
STATES = ("open", "resolved", "muted")

_SKIPPED_PATH = re.compile(r"^(/api/v\d+)?/(health|metrics|ping)(/|$|-|z)")
_EMAIL = re.compile(r"[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+")
_JWT = re.compile(r"eyJ[\w\-]+\.[\w\-]+\.[\w\-]*")
_BEARER = re.compile(r"(?i)\bbearer\s+\S+")
_UUID = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
_LONG_NUMBER = re.compile(r"\d{6,}")
_RECIPIENT = re.compile(r"^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$")
_APP_DIR = str(Path(__file__).resolve().parents[1]) + os.sep

_last_unavailable_warning = 0.0


def redact(text: str | None, limit: int = 300) -> str | None:
    if not text:
        return None
    text = _EMAIL.sub("[email]", text)
    text = _JWT.sub("[token]", text)
    text = _BEARER.sub("[token]", text)
    text = _UUID.sub("[id]", text)
    text = _LONG_NUMBER.sub("[n]", text)
    return text[:limit]


def fingerprint(
    service: str, kind: str, method: str, route: str, status: int,
    error_type: str | None = None, location: str | None = None,
) -> str:
    parts = [service, kind, method, route, str(status)]
    if kind == "error":
        parts += [error_type or "", location or ""]
    return hashlib.sha1("|".join(parts).encode()).hexdigest()


def location_from_exc(exc: BaseException | None) -> str | None:
    """`file.py:function` of the last traceback frame inside the app package."""
    if exc is None or exc.__traceback__ is None:
        return None
    found = None
    for frame in traceback.extract_tb(exc.__traceback__):
        if os.path.abspath(frame.filename).startswith(_APP_DIR):
            found = f"{os.path.basename(frame.filename)}:{frame.name}"
    return found


def is_skipped_path(path: str) -> bool:
    return bool(_SKIPPED_PATH.match(path))


def _event(
    service: str, kind: str, method: str, route: str, status: int,
    error_type: str | None, location: str | None, message: str | None, request_id: str | None,
) -> tuple[str, dict[str, Any]]:
    meta = {
        "service": service, "kind": kind, "method": method[:10].upper(), "route": route[:300],
        "status": status, "error_type": (error_type or None) and error_type[:150],
        "location": (location or None) and location[:200],
        "message": redact(message), "request_id": (request_id or None) and request_id[:100],
    }
    fp = fingerprint(service, kind, meta["method"], meta["route"], status, meta["error_type"], meta["location"])
    return fp, meta


def _queue(pipe: Any, fp: str, meta: dict[str, Any], count: int, now: float) -> None:
    minute = int(now // 60)
    window = WINDOW_KEY.format(fp=fp, minute=minute)
    pipe.hincrby(BUF_KEY, fp, count)
    pipe.set(META_KEY.format(fp=fp), json.dumps(meta), ex=META_TTL_SECONDS)
    pipe.incrby(window, count)
    pipe.expire(window, WINDOW_TTL_SECONDS)


def _warn_unavailable(reason: str) -> None:
    global _last_unavailable_warning
    if time.monotonic() - _last_unavailable_warning > 60:
        _last_unavailable_warning = time.monotonic()
        logger.warning("Error monitoring could not record an error: %s", reason)


async def record_error(
    *, service: str, kind: str, method: str, route: str, status: int,
    error_type: str | None = None, location: str | None = None,
    message: str | None = None, request_id: str | None = None, count: int = 1,
) -> bool:
    """Buffer one error in Redis. Never raises; False means it was dropped."""
    try:
        fp, meta = _event(service, kind, method, route, status, error_type, location, message, request_id)
        redis = await asyncio.wait_for(RedisClient.get_instance(), REDIS_TIMEOUT_SECONDS)
        if redis is None:
            _warn_unavailable("Redis is not connected")
            return False
        pipe = redis.pipeline(transaction=False)
        _queue(pipe, fp, meta, count, time.time())
        await asyncio.wait_for(pipe.execute(), REDIS_TIMEOUT_SECONDS)
        return True
    except Exception as exc:  # noqa: BLE001 - monitoring must never break a request
        _warn_unavailable(repr(exc))
        return False


_sync_client: Any = None


def record_error_sync(
    *, service: str, kind: str, method: str, route: str, status: int,
    error_type: str | None = None, location: str | None = None,
    message: str | None = None, request_id: str | None = None,
) -> bool:
    """Same as record_error for a Celery signal hook, which has no event loop to share."""
    global _sync_client
    try:
        if _sync_client is None:
            import redis

            _sync_client = redis.Redis.from_url(
                settings.REDIS_URL, password=settings.REDIS_PASSWORD,
                decode_responses=True, socket_connect_timeout=2, socket_timeout=2,
            )
        fp, meta = _event(service, kind, method, route, status, error_type, location, message, request_id)
        pipe = _sync_client.pipeline(transaction=False)
        _queue(pipe, fp, meta, 1, time.time())
        pipe.execute()
        return True
    except Exception as exc:  # noqa: BLE001
        _warn_unavailable(repr(exc))
        return False


def route_template(request: Request) -> str:
    return getattr(request.scope.get("route"), "path", None) or "<unmatched>"


async def record_request_error(
    request: Request, status: int, exc: BaseException | None = None, message: str | None = None
) -> None:
    """Record a failed backend request; `request.state.error_recorded` stops a second count."""
    try:
        if is_skipped_path(request.url.path) or status < 400:
            return
        kind = "error" if status >= 500 else "client"
        if kind == "error":
            if getattr(request.state, "error_recorded", False):
                return
            request.state.error_recorded = True
        await record_error(
            service="backend", kind=kind, method=request.method, route=route_template(request),
            status=status, error_type=type(exc).__name__ if exc else None,
            location=location_from_exc(exc),
            message=message if message is not None else (str(exc) if exc else None),
            request_id=getattr(request.state, "request_id", None),
        )
    except Exception as err:  # noqa: BLE001
        _warn_unavailable(repr(err))


@dataclass
class FlushedGroup:
    fingerprint: str
    kind: str
    count: int
    state_before: str | None
    is_new: bool
    regressed: bool


async def flush_buffer(db: AsyncSession, redis: Any, now: datetime | None = None) -> list[FlushedGroup]:
    """Move the Redis buffer into groups and hourly counts; returns what changed."""
    now = now or datetime.now(UTC)
    flushed: list[FlushedGroup] = []
    if not await redis.exists(FLUSHING_KEY):
        if not await redis.exists(BUF_KEY):
            return flushed
        await redis.rename(BUF_KEY, FLUSHING_KEY)
    counts = {fp: int(n) for fp, n in (await redis.hgetall(FLUSHING_KEY)).items()}
    if not counts:
        await redis.delete(FLUSHING_KEY)
        return flushed

    fps = list(counts)
    raw_meta = await redis.mget([META_KEY.format(fp=fp) for fp in fps])
    metas = {fp: json.loads(raw) for fp, raw in zip(fps, raw_meta, strict=True) if raw}
    existing = {
        g.fingerprint: g
        for g in (await db.execute(select(OpsErrorGroup).where(OpsErrorGroup.fingerprint.in_(fps)))).scalars()
    }

    rows: list[dict[str, Any]] = []
    for fp, n in counts.items():
        meta = metas.get(fp)
        group = existing.get(fp)
        if meta is None and group is None:
            continue
        before = group.state if group else None
        if meta is not None:
            row = {
                "fingerprint": fp, "service": meta["service"], "kind": meta["kind"], "method": meta["method"],
                "route": meta["route"], "status_code": meta["status"], "error_type": meta["error_type"],
                "location": meta["location"], "sample_message": meta["message"],
                "sample_request_id": meta["request_id"],
            }
        else:
            row = {
                "fingerprint": fp, "service": group.service, "kind": group.kind, "method": group.method,
                "route": group.route, "status_code": group.status_code, "error_type": group.error_type,
                "location": group.location, "sample_message": None, "sample_request_id": None,
            }
        rows.append({**row, "first_seen": now, "last_seen": now, "total_count": n, "reported_count": 0,
                     "state": "open", "regressed": False})
        flushed.append(FlushedGroup(fp, row["kind"], n, before, group is None, before == "resolved"))

    if rows:
        stmt = pg_insert(OpsErrorGroup).values(rows)
        excluded = stmt.excluded
        await db.execute(stmt.on_conflict_do_update(
            index_elements=["fingerprint"],
            set_={
                "total_count": OpsErrorGroup.total_count + excluded.total_count,
                "last_seen": excluded.last_seen,
                "sample_message": func.coalesce(excluded.sample_message, OpsErrorGroup.sample_message),
                "sample_request_id": func.coalesce(excluded.sample_request_id, OpsErrorGroup.sample_request_id),
                "regressed": case((OpsErrorGroup.state == "resolved", True), else_=OpsErrorGroup.regressed),
                "state": case((OpsErrorGroup.state == "resolved", "open"), else_=OpsErrorGroup.state),
            },
        ))
        bucket = now.replace(minute=0, second=0, microsecond=0)
        count_stmt = pg_insert(OpsErrorCount).values(
            [{"fingerprint": r["fingerprint"], "bucket_start": bucket, "count": r["total_count"]} for r in rows]
        )
        await db.execute(count_stmt.on_conflict_do_update(
            index_elements=["fingerprint", "bucket_start"],
            set_={"count": OpsErrorCount.count + count_stmt.excluded.count},
        ))
    await db.commit()
    await redis.delete(FLUSHING_KEY)
    return flushed


@dataclass
class ReportRow:
    service: str
    kind: str
    method: str
    route: str
    status: int
    error_type: str | None
    location: str | None
    message: str | None
    request_id: str | None
    count: int
    total: int
    new: bool = False
    regressed: bool = False


def _row(group: OpsErrorGroup, count: int) -> ReportRow:
    return ReportRow(
        group.service, group.kind, group.method, group.route, group.status_code, group.error_type,
        group.location, group.sample_message, group.sample_request_id, count, group.total_count,
        new=group.reported_count == 0, regressed=group.regressed,
    )


def _plural(n: int, word: str) -> str:
    return f"{n} {word}" if n == 1 else f"{n} {word}s"


def render_report(
    rows: list[ReportRow], *, minutes: int, alert: bool = False, link: str | None = None
) -> tuple[str, str, str]:
    """(subject, plain text, html) for a digest or an alert."""
    errors = sum(r.count for r in rows)
    tag = "[LexiLingo ALERT]" if alert else "[LexiLingo]"
    subject = f"{tag} {_plural(errors, 'error')} in {_plural(len(rows), 'group')} · last {minutes} min"
    by_service: dict[str, list[ReportRow]] = {}
    for r in sorted(rows, key=lambda r: r.count, reverse=True):
        by_service.setdefault(r.service, []).append(r)

    def flags(r: ReportRow) -> str:
        return " ".join(f for f, on in (("NEW", r.new), ("REGRESSED", r.regressed)) if on)

    text = [subject, ""]
    body = [f"<p style=\"font:14px/1.5 sans-serif\">{html.escape(subject)}</p>"]
    for service, items in by_service.items():
        shown = items[:MAX_ROWS_PER_SERVICE]
        text.append(f"== {service} ({_plural(sum(r.count for r in items), 'error')}) ==")
        body.append(f"<h3 style=\"font:600 15px sans-serif\">{html.escape(service)}</h3>")
        body.append(
            "<table cellpadding=\"6\" cellspacing=\"0\" border=\"1\" "
            "style=\"border-collapse:collapse;font:12px/1.4 sans-serif;border-color:#ddd\">"
            "<tr style=\"background:#f4f4f4;text-align:left\"><th>Count</th><th>Total</th><th>Request</th>"
            "<th>Status</th><th>Error</th><th>Where</th><th>Sample message</th><th>Request ID</th><th></th></tr>"
        )
        for r in shown:
            err = " ".join(filter(None, [r.error_type, r.location and f"({r.location})"])) or "-"
            text.append(
                f"{r.count:>5} (total {r.total}) {r.method} {r.route} -> {r.status}  {err}  "
                f"{(r.message or '-')}  req={r.request_id or '-'}  {flags(r)}".rstrip()
            )
            cells = [str(r.count), str(r.total), f"{r.method} {r.route}", str(r.status),
                     r.error_type or "-", r.location or "-", r.message or "-", r.request_id or "-",
                     f"<b>{flags(r)}</b>" if flags(r) else ""]
            body.append(
                "<tr>" + "".join(
                    f"<td>{c if i == 8 else html.escape(c)}</td>" for i, c in enumerate(cells)
                ) + "</tr>"
            )
        body.append("</table>")
        if len(items) > len(shown):
            more = f"... and {len(items) - len(shown)} more groups in {service}"
            text.append(more)
            body.append(f"<p style=\"font:12px sans-serif\">{html.escape(more)}</p>")
        text.append("")
    if link:
        text.append(f"Details: {link}")
        body.append(f"<p style=\"font:13px sans-serif\"><a href=\"{html.escape(link)}\">Open the Errors view</a></p>")
    return subject, "\n".join(text), "<html><body>" + "".join(body) + "</body></html>"


def admin_link() -> str:
    origins = settings.admin_web_origins
    return f"{origins[0]}/admin/ops" if origins else "/admin/ops"


async def send_report(recipients: list[str], subject: str, text: str, html_body: str) -> list[str]:
    from app.services.email_service import EmailService

    sent = []
    for to in recipients:
        if await EmailService.send_staff_message(to_email=to, subject=subject, text=text, html_body=html_body):
            sent.append(to)
    return sent


class ErrorReportSettingsUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: bool | None = None
    recipients: list[str] | None = None
    digest_interval_minutes: int | None = None
    spike_threshold: int | None = Field(None, ge=0, le=1_000_000)
    client_spike_threshold: int | None = Field(None, ge=0, le=1_000_000)
    cooldown_minutes: int | None = Field(None, ge=1, le=10_080)

    @field_validator("recipients")
    @classmethod
    def _recipients(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        cleaned = list(dict.fromkeys(v.strip().lower() for v in value if v and v.strip()))
        if not cleaned:
            raise ValueError("At least one recipient is required")
        if len(cleaned) > MAX_RECIPIENTS:
            raise ValueError(f"At most {MAX_RECIPIENTS} recipients")
        bad = [v for v in cleaned if not _RECIPIENT.match(v)]
        if bad:
            raise ValueError(f"Invalid email address: {bad[0]}")
        return cleaned

    @field_validator("digest_interval_minutes")
    @classmethod
    def _interval(cls, value: int | None) -> int | None:
        if value is not None and value not in DIGEST_INTERVALS:
            raise ValueError(f"digest_interval_minutes must be one of {list(DIGEST_INTERVALS)}")
        return value


def _default_settings() -> dict[str, Any]:
    recipients = [r.strip() for r in settings.OPS_ERROR_REPORT_RECIPIENTS.split(",") if r.strip()]
    return {
        "enabled": True, "recipients": recipients or ["support@lexilingo.me"],
        "digest_interval_minutes": 60, "spike_threshold": 20, "client_spike_threshold": 200,
        "cooldown_minutes": 60,
    }


async def get_report_settings(db: AsyncSession) -> dict[str, Any]:
    rows = (
        await db.execute(select(AppSetting).where(AppSetting.key.in_([SETTINGS_KEY, LAST_DIGEST_KEY])))
    ).scalars().all()
    stored = {row.key: row.value for row in rows}
    values = _default_settings()
    saved = stored.get(SETTINGS_KEY)
    if isinstance(saved, dict):
        values.update({k: v for k, v in saved.items() if k in values})
    last = stored.get(LAST_DIGEST_KEY)
    values["last_digest_at"] = last if isinstance(last, str) else None
    return values


async def _put_setting(db: AsyncSession, key: str, value: Any, admin_id: uuid.UUID | None) -> None:
    row = await db.get(AppSetting, key)
    if row is None:
        db.add(AppSetting(key=key, value=value, updated_by=admin_id))
    else:
        row.value = value
        row.updated_by = admin_id


async def set_report_settings(
    db: AsyncSession, admin_id: uuid.UUID, update_in: ErrorReportSettingsUpdate
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Returns (before, after) of the changed keys. The caller commits."""
    current = await get_report_settings(db)
    changes = {k: v for k, v in update_in.model_dump(exclude_none=True).items() if current[k] != v}
    if changes:
        merged = {k: current[k] for k in _default_settings()}
        merged.update(changes)
        await _put_setting(db, SETTINGS_KEY, merged, admin_id)
    return {k: current[k] for k in changes}, changes


def _parse_dt(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


@dataclass
class Alert:
    fingerprint: str
    reason: str
    window_count: int


async def detect_alerts(
    redis: Any, flushed: list[FlushedGroup], cfg: dict[str, Any], now: float | None = None
) -> list[Alert]:
    """New or regressed 5xx groups and groups over their spike threshold, once per cooldown."""
    now = now or time.time()
    minute = int(now // 60)
    alerts: list[Alert] = []
    for g in flushed:
        if g.state_before == "muted":
            continue
        keys = [WINDOW_KEY.format(fp=g.fingerprint, minute=minute - i) for i in range(SPIKE_WINDOW_MINUTES)]
        window = sum(int(v) for v in await redis.mget(keys) if v)
        threshold = cfg["spike_threshold"] if g.kind == "error" else cfg["client_spike_threshold"]
        reason = None
        if g.kind == "error" and g.is_new:
            reason = "new"
        elif g.kind == "error" and g.regressed:
            reason = "regressed"
        elif threshold > 0 and window >= threshold:
            reason = "spike"
        if reason is None:
            continue
        taken = await redis.set(
            ALERTED_KEY.format(fp=g.fingerprint), "1", nx=True, ex=int(cfg["cooldown_minutes"]) * 60
        )
        if taken:
            alerts.append(Alert(g.fingerprint, reason, max(window, g.count)))
    return alerts


async def run_flush(db: AsyncSession, redis: Any) -> dict[str, int]:
    """One flush tick: buffer to rows, then a single alert mail for what crossed a line."""
    flushed = await flush_buffer(db, redis)
    cfg = await get_report_settings(db)
    alerts = await detect_alerts(redis, flushed, cfg) if flushed and cfg["enabled"] else []
    sent = 0
    if alerts:
        groups = {
            g.fingerprint: g
            for g in (
                await db.execute(select(OpsErrorGroup).where(OpsErrorGroup.fingerprint.in_([a.fingerprint for a in alerts])))
            ).scalars()
        }
        rows = []
        for a in alerts:
            row = _row(groups[a.fingerprint], a.window_count)
            row.new = a.reason == "new"
            rows.append(row)
        subject, text, body = render_report(rows, minutes=SPIKE_WINDOW_MINUTES, alert=True, link=admin_link())
        sent = len(await send_report(cfg["recipients"], subject, text, body))
    return {"groups": len(flushed), "alerts": len(alerts), "mails": sent}


async def select_digest(db: AsyncSession, cfg: dict[str, Any]) -> tuple[list[ReportRow], dict[str, int]]:
    """Rows worth mailing, plus every group's seen total so a send can mark them all reported."""
    groups = (
        await db.execute(select(OpsErrorGroup).where(OpsErrorGroup.total_count > OpsErrorGroup.reported_count))
    ).scalars().all()
    rows: list[ReportRow] = []
    seen: dict[str, int] = {}
    for g in groups:
        seen[g.fingerprint] = g.total_count
        if g.state != "open":
            continue
        period = g.total_count - g.reported_count
        if g.kind == "client" and not (cfg["client_spike_threshold"] > 0 and period >= cfg["client_spike_threshold"]):
            continue
        rows.append(_row(g, period))
    return rows, seen


async def run_digest(db: AsyncSession, now: datetime | None = None) -> dict[str, Any]:
    """Mail the period's new errors when the interval has passed; only then advance the baseline."""
    now = now or datetime.now(UTC)
    cfg = await get_report_settings(db)
    if not cfg["enabled"]:
        return {"skipped": "disabled"}
    last = _parse_dt(cfg["last_digest_at"])
    if last is not None and now - last < timedelta(minutes=cfg["digest_interval_minutes"]):
        return {"skipped": "not due"}
    rows, seen = await select_digest(db, cfg)
    if not rows:
        return {"skipped": "no new errors"}
    subject, text, body = render_report(rows, minutes=cfg["digest_interval_minutes"], link=admin_link())
    sent = await send_report(cfg["recipients"], subject, text, body)
    if not sent:
        return {"skipped": "send failed"}
    for fp, total in seen.items():
        await db.execute(update(OpsErrorGroup).where(OpsErrorGroup.fingerprint == fp).values(reported_count=total))
    await _put_setting(db, LAST_DIGEST_KEY, now.isoformat(), None)
    await db.commit()
    return {"groups": len(rows), "sent_to": sent}


async def send_test_report(db: AsyncSession) -> tuple[list[str], int]:
    """The current period's digest, or a short all-clear. Baselines stay where they are."""
    cfg = await get_report_settings(db)
    rows, _ = await select_digest(db, cfg)
    minutes = cfg["digest_interval_minutes"]
    if rows:
        subject, text, body = render_report(rows, minutes=minutes, link=admin_link())
    else:
        subject = f"[LexiLingo] Test report: no new errors in the last {minutes} min"
        text = f"{subject}\n\nDetails: {admin_link()}"
        body = f"<p style=\"font:14px sans-serif\">{html.escape(subject)}</p>"
    return await send_report(cfg["recipients"], subject, text, body), len(rows)


async def prune_counts(db: AsyncSession, now: datetime | None = None) -> int:
    cutoff = (now or datetime.now(UTC)) - timedelta(days=RETENTION_DAYS)
    result = await db.execute(delete(OpsErrorCount).where(OpsErrorCount.bucket_start < cutoff))
    await db.commit()
    return result.rowcount or 0


def group_dict(group: OpsErrorGroup, count_window: int) -> dict[str, Any]:
    return {
        "fingerprint": group.fingerprint, "service": group.service, "kind": group.kind,
        "method": group.method, "route": group.route, "status_code": group.status_code,
        "error_type": group.error_type, "location": group.location,
        "sample_message": group.sample_message, "sample_request_id": group.sample_request_id,
        "first_seen": group.first_seen.isoformat(), "last_seen": group.last_seen.isoformat(),
        "total_count": group.total_count, "count_window": count_window,
        "state": group.state, "regressed": group.regressed,
    }
