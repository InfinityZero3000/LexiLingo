"""Persistence model for the Notification Campaign Agent workflow."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


def _utcnow() -> datetime:
    return datetime.now(UTC)


class NotificationCampaignJob(Base):
    __tablename__ = "notification_campaign_jobs"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    requested_by_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    job_type: Mapped[str] = mapped_column(
        String(32), nullable=False, index=True
    )  # targeted_push | in_app_broadcast | scheduled_push
    status: Mapped[str] = mapped_column(
        String(32), default="queued", nullable=False, index=True
    )  # queued → segmenting → generating → validating → preview_ready → sending → completed | failed | cancelled
    progress: Mapped[dict] = mapped_column(PortableJSON, default=dict, nullable=False)
    config: Mapped[dict] = mapped_column(PortableJSON, nullable=False)
    artifact: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    warnings: Mapped[list] = mapped_column(PortableJSON, default=list, nullable=False)
    blocking_errors: Mapped[list] = mapped_column(PortableJSON, default=list, nullable=False)
    delivery_stats: Mapped[dict] = mapped_column(
        PortableJSON, default=dict, nullable=False
    )  # {sent, failed, skipped, total}
    celery_task_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=_utcnow, nullable=False, index=True)
    updated_at: Mapped[datetime] = mapped_column(TZDateTime, default=_utcnow, onupdate=_utcnow, nullable=False)
    started_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    scheduled_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)

    __table_args__ = (
        Index("ix_notification_campaign_type_status", "job_type", "status"),
    )

    def __repr__(self) -> str:
        return f"<NotificationCampaignJob {self.id} type={self.job_type} status={self.status}>"
