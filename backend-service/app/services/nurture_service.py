"""Activation, streak-at-risk and weekly-summary nudges, deduped by a notifications row."""

from __future__ import annotations

import asyncio
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import delete, exists, func, select
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core.config import settings
from app.core.real_users import real_user_clause
from app.models.games import XPTransaction
from app.models.notification import Notification
from app.models.progress import DailyActivity, LessonCompletion, Streak, UserProgress
from app.models.reminder import UserReminderPreference
from app.models.user import User, UserDevice
from app.services.email_service import EmailService, is_undeliverable
from app.services.push_notification_service import PushNotificationService

logger = logging.getLogger(__name__)

D1 = "nurture_d1"
D3 = "nurture_d3"
STREAK_RISK = "streak_risk_email"
WEEKLY = "weekly_summary"

# Age of the account, in hours, in which each activation nudge is due.
_ACTIVATION_WINDOWS = {D1: (24, 48), D3: (72, 96)}


@dataclass(frozen=True)
class Recipient:
    user_id: uuid.UUID
    email: str
    display_name: str | None
    period: str
    streak_days: int = 0
    xp: int = 0
    words: int = 0


def _eligible_user():
    # Aliased: the streak query joins the same table, and a correlated EXISTS
    # on it would lose its FROM to that join.
    optout = aliased(UserReminderPreference)
    return (
        User.is_active.is_(True),
        User.is_verified.is_(True),
        real_user_clause(),
        ~exists().where(optout.user_id == User.id, optout.nurture_emails_enabled.is_(False)),
    )


def _has_device():
    return exists().where(UserDevice.user_id == User.id, UserDevice.fcm_token.isnot(None))


def _zone(name: str | None) -> ZoneInfo:
    for candidate in (name, settings.REMINDER_DEFAULT_TIMEZONE):
        try:
            return ZoneInfo(candidate or "")
        except (ZoneInfoNotFoundError, ValueError):
            continue
    return ZoneInfo("UTC")


def _link(route: str) -> str:
    return f"{settings.APP_PUBLIC_URL.rstrip('/')}{route}"


async def _already_sent(
    db: AsyncSession, user_ids: list[uuid.UUID], kind: str, period: str
) -> set[uuid.UUID]:
    if not user_ids:
        return set()
    rows = await db.execute(
        select(Notification.user_id).where(
            Notification.user_id.in_(user_ids),
            Notification.type == kind,
            Notification.dedupe_key == period,
        )
    )
    return set(rows.scalars())


async def select_activation(db: AsyncSession, kind: str, now: datetime) -> list[Recipient]:
    low, high = _ACTIVATION_WINDOWS[kind]
    rows = (
        await db.execute(
            select(User.id, User.email, User.display_name)
            .where(
                *_eligible_user(),
                User.created_at <= now - timedelta(hours=low),
                User.created_at > now - timedelta(hours=high),
                ~exists().where(
                    UserProgress.user_id == User.id, UserProgress.status == "completed"
                ),
                ~exists().where(LessonCompletion.user_id == User.id),
            )
            .order_by(User.created_at)
        )
    ).all()
    rows = [r for r in rows if not is_undeliverable(r.email)]
    done = await _already_sent(db, [r.id for r in rows], kind, kind)
    return [Recipient(r.id, r.email, r.display_name, kind) for r in rows if r.id not in done]


async def select_streak_risk(db: AsyncSession, now: datetime) -> list[Recipient]:
    utc_today = now.date()
    rows = (
        await db.execute(
            select(
                User.id,
                User.email,
                User.display_name,
                Streak.current_streak,
                Streak.last_activity_date,
                UserReminderPreference.timezone,
            )
            .join(Streak, Streak.user_id == User.id)
            .outerjoin(UserReminderPreference, UserReminderPreference.user_id == User.id)
            .where(
                *_eligible_user(),
                ~_has_device(),
                Streak.current_streak > 0,
                Streak.last_activity_date >= utc_today - timedelta(days=2),
            )
        )
    ).all()

    due: list[tuple] = []
    for row in rows:
        local = now.astimezone(_zone(row.timezone))
        if local.hour != settings.NURTURE_STREAK_LOCAL_HOUR or is_undeliverable(row.email):
            continue
        local_today = local.date()
        last = row.last_activity_date
        if last >= local_today or last < local_today - timedelta(days=1):
            continue
        midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
        due.append((row, local_today.isoformat(), midnight.astimezone(timezone.utc)))

    out: list[Recipient] = []
    for row, period, midnight_utc in due:
        # Streak dates are UTC dates; any XP since local midnight also counts as practice.
        practised = await db.scalar(
            select(XPTransaction.id)
            .where(XPTransaction.user_id == row.id, XPTransaction.created_at >= midnight_utc)
            .limit(1)
        )
        if not practised:
            out.append(
                Recipient(row.id, row.email, row.display_name, period, streak_days=row.current_streak)
            )
    sent = {
        (uid, key)
        for uid, key in (
            await db.execute(
                select(Notification.user_id, Notification.dedupe_key).where(
                    Notification.type == STREAK_RISK,
                    Notification.user_id.in_([r.user_id for r in out] or [None]),
                )
            )
        ).all()
    }
    return [r for r in out if (r.user_id, r.period) not in sent]


async def select_weekly(db: AsyncSession, now: datetime) -> list[Recipient]:
    today = now.date()
    year, week, _ = today.isocalendar()
    period = f"{year}-W{week:02d}"
    week_start = today - timedelta(days=6)
    rows = (
        await db.execute(
            select(
                User.id,
                User.email,
                User.display_name,
                func.coalesce(
                    select(func.sum(DailyActivity.xp_earned))
                    .where(DailyActivity.user_id == User.id, DailyActivity.activity_date >= week_start)
                    .scalar_subquery(),
                    0,
                ).label("xp"),
                func.coalesce(
                    select(func.sum(DailyActivity.vocabulary_reviewed))
                    .where(DailyActivity.user_id == User.id, DailyActivity.activity_date >= week_start)
                    .scalar_subquery(),
                    0,
                ).label("words"),
                func.coalesce(
                    select(Streak.current_streak).where(Streak.user_id == User.id).scalar_subquery(), 0
                ).label("streak"),
            )
            .where(
                *_eligible_user(),
                exists().where(
                    DailyActivity.user_id == User.id,
                    DailyActivity.activity_date >= today - timedelta(days=14),
                ),
            )
            .order_by(User.id)
        )
    ).all()
    rows = [r for r in rows if not is_undeliverable(r.email)]
    done = await _already_sent(db, [r.id for r in rows], WEEKLY, period)
    return [
        Recipient(r.id, r.email, r.display_name, period, streak_days=r.streak, xp=r.xp, words=r.words)
        for r in rows
        if r.id not in done
    ]


async def _claim(
    db: AsyncSession, recipient: Recipient, kind: str, title: str, body: str, route: str
) -> bool:
    """Insert the inbox row; False when this (user, type, period) already has one."""
    dialect = db.get_bind().dialect.name
    insert = (postgresql if dialect == "postgresql" else sqlite).insert
    statement = (
        insert(Notification)
        .values(
            id=uuid.uuid4(),
            user_id=recipient.user_id,
            type=kind,
            title=title,
            body=body,
            data={"route": route, "period": recipient.period},
            dedupe_key=recipient.period,
            is_read=False,
            created_at=datetime.now(timezone.utc),
        )
        .on_conflict_do_nothing(
            index_elements=["user_id", "type", "dedupe_key"],
            index_where=Notification.dedupe_key.isnot(None),
        )
        .returning(Notification.id)
    )
    claimed = (await db.execute(statement)).scalar_one_or_none() is not None
    await db.commit()
    return claimed


async def _release(db: AsyncSession, recipient: Recipient, kind: str) -> None:
    await db.execute(
        delete(Notification).where(
            Notification.user_id == recipient.user_id,
            Notification.type == kind,
            Notification.dedupe_key == recipient.period,
        )
    )
    await db.commit()


async def _tokens(db: AsyncSession, user_id: uuid.UUID) -> list[str]:
    rows = await db.execute(
        select(UserDevice.fcm_token).where(
            UserDevice.user_id == user_id, UserDevice.fcm_token.isnot(None)
        )
    )
    return [t for t in rows.scalars() if t]


async def _deliver(
    db: AsyncSession,
    recipients: list[Recipient],
    kind: str,
    copy,
    route: str,
    send,
) -> dict[str, int]:
    """Claim, send, and give the claim back when nothing went out."""
    result = {"selected": len(recipients), "sent": 0, "duplicate": 0, "failed": 0, "deferred": 0}
    batch = recipients[: settings.NURTURE_MAX_PER_RUN]
    result["deferred"] = len(recipients) - len(batch)
    for recipient in batch:
        title, body = copy(recipient)
        if not await _claim(db, recipient, kind, title, body, route):
            result["duplicate"] += 1
            continue
        try:
            delivered = await send(recipient, title, body)
        except Exception:
            logger.exception("Nurture %s send crashed", kind)
            delivered = False
        if delivered:
            result["sent"] += 1
        else:
            result["failed"] += 1
            await _release(db, recipient, kind)
        await asyncio.sleep(settings.NURTURE_SEND_DELAY_SECONDS)
    return result


def _dry(kind: str, recipients: list[Recipient]) -> dict[str, int | str]:
    logger.info("nurture %s dry run: would send %d (flag off)", kind, len(recipients))
    return {"kind": kind, "mode": "dry_run", "would_send": len(recipients)}


async def run_activation(db: AsyncSession, kind: str, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    recipients = await select_activation(db, kind, now)
    if not settings.NURTURE_EMAILS_ENABLED:
        return _dry(kind, recipients)

    day = 1 if kind == D1 else 3
    route = settings.NURTURE_START_ROUTE
    push = PushNotificationService()

    def copy(_r: Recipient) -> tuple[str, str]:
        if day == 1:
            return "Your first lesson is ready", "One short lesson is enough to begin. Tap to start."
        return "Still want to start?", "Your first lesson is waiting. Five minutes is enough."

    async def send(r: Recipient, title: str, body: str) -> bool:
        emailed = await EmailService.send_activation_nudge_email(
            to_email=r.email,
            display_name=r.display_name,
            user_id=r.user_id,
            day=day,
            start_link=_link(route),
        )
        tokens = await _tokens(db, r.user_id)
        pushed = bool(tokens) and await push.send_nurture(
            tokens=tokens, kind=kind, title=title, body=body, route=route
        )
        return bool(emailed or pushed)

    return {"kind": kind, "mode": "live", **await _deliver(db, recipients, kind, copy, route, send)}


async def run_streak_risk(db: AsyncSession, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    recipients = await select_streak_risk(db, now)
    if not settings.NURTURE_EMAILS_ENABLED:
        return _dry(STREAK_RISK, recipients)

    route = settings.REMINDER_REVIEW_ROUTE

    def copy(r: Recipient) -> tuple[str, str]:
        return "Keep your streak alive", f"Your {r.streak_days}-day streak ends tonight. A few minutes is enough."

    async def send(r: Recipient, _title: str, _body: str) -> bool:
        return await EmailService.send_streak_at_risk_email(
            to_email=r.email, display_name=r.display_name, user_id=r.user_id, streak_days=r.streak_days
        )

    return {"kind": STREAK_RISK, "mode": "live", **await _deliver(db, recipients, STREAK_RISK, copy, route, send)}


async def run_weekly(db: AsyncSession, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    recipients = await select_weekly(db, now)
    if not settings.NURTURE_EMAILS_ENABLED:
        return _dry(WEEKLY, recipients)

    route = "/"

    def copy(r: Recipient) -> tuple[str, str]:
        return "Your week in LexiLingo", f"{r.xp:,} XP and a {r.streak_days}-day streak in the last 7 days."

    async def send(r: Recipient, _title: str, _body: str) -> bool:
        return await EmailService.send_weekly_summary_email(
            to_email=r.email,
            display_name=r.display_name,
            user_id=r.user_id,
            xp=r.xp,
            streak_days=r.streak_days,
            words_learned=r.words,
        )

    return {"kind": WEEKLY, "mode": "live", **await _deliver(db, recipients, WEEKLY, copy, route, send)}
