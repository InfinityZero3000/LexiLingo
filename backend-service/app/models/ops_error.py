"""Grouped request/task errors and their hourly counts, for the admin Errors view and email reports."""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime


class OpsErrorGroup(Base):
    __tablename__ = "ops_error_groups"
    __table_args__ = (Index("ix_ops_error_groups_last_seen", "last_seen"),)

    fingerprint: Mapped[str] = mapped_column(String(40), primary_key=True)
    service: Mapped[str] = mapped_column(String(30), nullable=False)
    kind: Mapped[str] = mapped_column(String(10), nullable=False)
    method: Mapped[str] = mapped_column(String(10), nullable=False)
    route: Mapped[str] = mapped_column(String(300), nullable=False)
    status_code: Mapped[int] = mapped_column(Integer, nullable=False)
    error_type: Mapped[str | None] = mapped_column(String(150), nullable=True)
    location: Mapped[str | None] = mapped_column(String(200), nullable=True)
    sample_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    sample_request_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    first_seen: Mapped[datetime] = mapped_column(TZDateTime, nullable=False)
    last_seen: Mapped[datetime] = mapped_column(TZDateTime, nullable=False)
    total_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reported_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    state: Mapped[str] = mapped_column(String(10), nullable=False, default="open")
    regressed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    state_changed_by: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    state_changed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)


class OpsErrorCount(Base):
    __tablename__ = "ops_error_counts"

    fingerprint: Mapped[str] = mapped_column(
        String(40), ForeignKey("ops_error_groups.fingerprint", ondelete="CASCADE"), primary_key=True
    )
    bucket_start: Mapped[datetime] = mapped_column(TZDateTime, primary_key=True)
    count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
