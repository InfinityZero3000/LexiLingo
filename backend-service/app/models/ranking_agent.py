"""Persistence model for the Ranking/Gamification Agent workflow."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


def _utcnow() -> datetime:
    return datetime.now(UTC)


class RankingAgentJob(Base):
    __tablename__ = "ranking_agent_jobs"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    requested_by_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    job_type: Mapped[str] = mapped_column(
        String(32), nullable=False, index=True
    )  # league_reset | xp_event | achievement_batch
    status: Mapped[str] = mapped_column(
        String(32), default="queued", nullable=False, index=True
    )
    progress: Mapped[dict] = mapped_column(PortableJSON, default=dict, nullable=False)
    config: Mapped[dict] = mapped_column(PortableJSON, nullable=False)
    artifact: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    warnings: Mapped[list] = mapped_column(PortableJSON, default=list, nullable=False)
    blocking_errors: Mapped[list] = mapped_column(
        PortableJSON, default=list, nullable=False
    )
    created_entity_ids: Mapped[dict] = mapped_column(
        PortableJSON, default=dict, nullable=False
    )
    celery_task_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        TZDateTime, default=_utcnow, nullable=False, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime, default=_utcnow, onupdate=_utcnow, nullable=False
    )
    started_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)

    __table_args__ = (
        Index("ix_ranking_agent_job_type_status", "job_type", "status"),
    )

    def __repr__(self) -> str:
        return f"<RankingAgentJob {self.id} type={self.job_type} status={self.status}>"
