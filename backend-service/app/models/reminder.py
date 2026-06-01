"""Reminder preferences and delivery audit models."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


class UserReminderPreference(Base):
    """Per-user settings for FSRS review reminders."""

    __tablename__ = "user_reminder_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    push_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    email_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    reminder_time_local: Mapped[str] = mapped_column(
        String(5),
        default="09:00",
        nullable=False,
    )
    timezone: Mapped[str] = mapped_column(
        String(64),
        default="Asia/Ho_Chi_Minh",
        nullable=False,
    )
    min_due_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    email_cadence_days: Mapped[int] = mapped_column(Integer, default=7, nullable=False)
    next_check_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )
    last_push_sent_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    last_email_sent_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    __table_args__ = (
        Index("ix_user_reminder_preferences_enabled_next", "enabled", "next_check_at"),
    )


class ReminderDelivery(Base):
    """Audit and idempotency record for reminder side effects."""

    __tablename__ = "reminder_deliveries"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    channel: Mapped[str] = mapped_column(String(20), nullable=False)
    reminder_type: Mapped[str] = mapped_column(
        String(50),
        default="vocabulary_review",
        nullable=False,
    )
    status: Mapped[str] = mapped_column(String(20), default="queued", nullable=False)
    due_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    dedupe_key: Mapped[str] = mapped_column(String(180), nullable=False)
    scheduled_for: Mapped[datetime] = mapped_column(TZDateTime, nullable=False, index=True)
    sent_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    error: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    data: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime,
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint("dedupe_key", name="uq_reminder_deliveries_dedupe_key"),
        Index("ix_reminder_delivery_user_channel_created", "user_id", "channel", "created_at"),
    )
