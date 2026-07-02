"""FSRS review reminder orchestration service."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.notification import Notification
from app.models.reminder import ReminderDelivery, UserReminderPreference
from app.models.user import User, UserDevice
from app.services.email_service import EmailService
from app.services.fsrs_scheduler_service import FSRSSchedulerService
from app.services.push_notification_service import PushNotificationService

logger = logging.getLogger(__name__)


@dataclass
class ReminderProcessResult:
    processed: int = 0
    sent: int = 0
    skipped: int = 0
    failed: int = 0
    dry_run: int = 0

    def to_dict(self) -> dict[str, int]:
        return {
            "processed": self.processed,
            "sent": self.sent,
            "skipped": self.skipped,
            "failed": self.failed,
            "dry_run": self.dry_run,
        }


class ReminderService:
    """Coordinates due checks, dedupe, notifications, push, and email."""

    def __init__(
        self,
        *,
        fsrs_scheduler: FSRSSchedulerService | None = None,
        push_service: PushNotificationService | None = None,
        email_service: type[EmailService] = EmailService,
    ) -> None:
        self.fsrs_scheduler = fsrs_scheduler or FSRSSchedulerService()
        self.push_service = push_service or PushNotificationService()
        self.email_service = email_service

    def _zoneinfo(self, timezone_name: str) -> ZoneInfo:
        try:
            return ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError:
            return ZoneInfo(settings.REMINDER_DEFAULT_TIMEZONE)

    def local_date_key(self, preference: UserReminderPreference, now_utc: datetime) -> str:
        local_time = now_utc.astimezone(self._zoneinfo(preference.timezone))
        return local_time.date().isoformat()

    def build_dedupe_key(
        self,
        *,
        user_id: UUID,
        channel: str,
        local_date: str,
    ) -> str:
        return f"vocabulary_review:{user_id}:{local_date}:{channel}"

    def compute_next_check_at(
        self,
        *,
        reminder_time_local: str,
        timezone_name: str,
        now_utc: datetime,
    ) -> datetime:
        local_tz = self._zoneinfo(timezone_name)
        hour, minute = [int(part) for part in reminder_time_local.split(":")]
        local_now = now_utc.astimezone(local_tz)
        candidate = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if candidate <= local_now:
            candidate = candidate + timedelta(days=1)
        return candidate.astimezone(timezone.utc)

    async def scan_due_preferences(
        self,
        db: AsyncSession,
        *,
        now_utc: datetime | None = None,
        limit: int | None = None,
    ) -> dict:
        """Process enabled preferences whose reminder time is due."""
        if not settings.REMINDERS_ENABLED:
            return {
                "processed": 0,
                "sent": 0,
                "skipped": 0,
                "failed": 0,
                "dry_run": 0,
                "reason": "disabled",
            }

        now_utc = now_utc or datetime.now(timezone.utc)
        result = await db.execute(
            select(UserReminderPreference)
            .where(
                UserReminderPreference.enabled.is_(True),
                UserReminderPreference.next_check_at <= now_utc,
            )
            .order_by(UserReminderPreference.next_check_at)
            .limit(limit or settings.REMINDER_SCAN_BATCH_SIZE)
        )
        preferences = result.scalars().all()

        totals = ReminderProcessResult()
        for preference in preferences:
            partial = await self.process_preference(db, preference=preference, now_utc=now_utc)
            totals.processed += partial.processed
            totals.sent += partial.sent
            totals.skipped += partial.skipped
            totals.failed += partial.failed
            totals.dry_run += partial.dry_run

        return totals.to_dict()

    async def process_preference(
        self,
        db: AsyncSession,
        *,
        preference: UserReminderPreference,
        now_utc: datetime,
    ) -> ReminderProcessResult:
        """Process one user's reminder preference."""
        result = ReminderProcessResult(processed=1)
        user = await self._get_user(db, preference.user_id)
        if not user or not user.is_active:
            result.skipped += 1
            preference.next_check_at = self.compute_next_check_at(
                reminder_time_local=preference.reminder_time_local,
                timezone_name=preference.timezone,
                now_utc=now_utc,
            )
            return result

        due_count = await self.fsrs_scheduler.count_due_vocabulary(
            db,
            user_id=preference.user_id,
            now=now_utc,
        )
        if due_count < preference.min_due_count:
            result.skipped += 1
            preference.next_check_at = self.compute_next_check_at(
                reminder_time_local=preference.reminder_time_local,
                timezone_name=preference.timezone,
                now_utc=now_utc,
            )
            return result

        local_date = self.local_date_key(preference, now_utc)
        if preference.push_enabled:
            push_status = await self._send_push(
                db,
                user=user,
                preference=preference,
                due_count=due_count,
                local_date=local_date,
                now_utc=now_utc,
            )
            self._accumulate_status(result, push_status)

        if preference.email_enabled:
            email_status = await self._send_email(
                db,
                user=user,
                preference=preference,
                due_count=due_count,
                local_date=local_date,
                now_utc=now_utc,
            )
            self._accumulate_status(result, email_status)

        if not preference.push_enabled and not preference.email_enabled:
            result.skipped += 1

        preference.next_check_at = self.compute_next_check_at(
            reminder_time_local=preference.reminder_time_local,
            timezone_name=preference.timezone,
            now_utc=now_utc,
        )
        return result

    async def _get_user(self, db: AsyncSession, user_id: UUID) -> User | None:
        result = await db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    async def _delivery_exists(
        self,
        db: AsyncSession,
        *,
        dedupe_key: str,
    ) -> bool:
        result = await db.execute(
            select(ReminderDelivery.id).where(ReminderDelivery.dedupe_key == dedupe_key)
        )
        return result.scalar_one_or_none() is not None

    async def _create_delivery(
        self,
        db: AsyncSession,
        *,
        preference: UserReminderPreference,
        channel: str,
        due_count: int,
        dedupe_key: str,
        now_utc: datetime,
    ) -> ReminderDelivery:
        delivery = ReminderDelivery(
            user_id=preference.user_id,
            channel=channel,
            status="queued",
            due_count=due_count,
            dedupe_key=dedupe_key,
            scheduled_for=now_utc,
            data={
                "route": settings.REMINDER_REVIEW_ROUTE,
                "timezone": preference.timezone,
                "reminder_time_local": preference.reminder_time_local,
            },
        )
        db.add(delivery)
        await db.flush()
        return delivery

    def _title_body(self, due_count: int) -> tuple[str, str]:
        word_label = "word" if due_count == 1 else "words"
        return (
            "Vocabulary review is ready",
            f"You have {due_count} {word_label} to review.",
        )

    async def _send_push(
        self,
        db: AsyncSession,
        *,
        user: User,
        preference: UserReminderPreference,
        due_count: int,
        local_date: str,
        now_utc: datetime,
    ) -> str:
        dedupe_key = self.build_dedupe_key(
            user_id=preference.user_id,
            channel="push",
            local_date=local_date,
        )
        if await self._delivery_exists(db, dedupe_key=dedupe_key):
            return "duplicate"

        delivery = await self._create_delivery(
            db,
            preference=preference,
            channel="push",
            due_count=due_count,
            dedupe_key=dedupe_key,
            now_utc=now_utc,
        )
        if settings.REMINDER_DRY_RUN:
            delivery.status = "dry_run"
            return "dry_run"

        title, body = self._title_body(due_count)
        db.add(
            Notification(
                user_id=user.id,
                title=title,
                body=body,
                type="vocabulary_review_reminder",
                data={
                    "route": settings.REMINDER_REVIEW_ROUTE,
                    "due_count": due_count,
                },
            )
        )
        tokens = await self._get_fcm_tokens(db, user.id)
        sent = await self.push_service.send_review_reminder(
            tokens=tokens,
            due_count=due_count,
            title=title,
            body=body,
            data={
                "route": settings.REMINDER_REVIEW_ROUTE,
                "due_count": str(due_count),
            },
        )
        if sent:
            delivery.status = "sent"
            delivery.sent_at = now_utc
            preference.last_push_sent_at = now_utc
            return "sent"

        delivery.status = "skipped"
        delivery.error = "No push token or FCM unavailable"
        return "skipped"

    async def _get_fcm_tokens(self, db: AsyncSession, user_id: UUID) -> list[str]:
        result = await db.execute(
            select(UserDevice.fcm_token).where(
                and_(
                    UserDevice.user_id == user_id,
                    UserDevice.fcm_token.is_not(None),
                )
            )
        )
        return [token for token in result.scalars().all() if token]

    async def _send_email(
        self,
        db: AsyncSession,
        *,
        user: User,
        preference: UserReminderPreference,
        due_count: int,
        local_date: str,
        now_utc: datetime,
    ) -> str:
        if (
            preference.last_email_sent_at
            and now_utc - preference.last_email_sent_at
            < timedelta(days=preference.email_cadence_days)
        ):
            return "skipped"

        dedupe_key = self.build_dedupe_key(
            user_id=preference.user_id,
            channel="email",
            local_date=local_date,
        )
        if await self._delivery_exists(db, dedupe_key=dedupe_key):
            return "duplicate"

        delivery = await self._create_delivery(
            db,
            preference=preference,
            channel="email",
            due_count=due_count,
            dedupe_key=dedupe_key,
            now_utc=now_utc,
        )
        if settings.REMINDER_DRY_RUN:
            delivery.status = "dry_run"
            return "dry_run"

        sent = await self.email_service.send_vocabulary_review_reminder_email(
            to_email=user.email,
            display_name=user.display_name or user.username,
            due_count=due_count,
        )
        if sent:
            delivery.status = "sent"
            delivery.sent_at = now_utc
            preference.last_email_sent_at = now_utc
            return "sent"

        delivery.status = "failed"
        delivery.error = "SMTP unavailable or send failed"
        return "failed"

    def _accumulate_status(self, result: ReminderProcessResult, status: str) -> None:
        if status == "sent":
            result.sent += 1
        elif status == "dry_run":
            result.dry_run += 1
        elif status == "failed":
            result.failed += 1
        else:
            result.skipped += 1
