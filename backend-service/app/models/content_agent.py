"""Persistence models for the CEFR content-agent workflow."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, PortableJSON, TZDateTime


def _utcnow() -> datetime:
    return datetime.now(UTC)


class ContentAgentUpload(Base):
    __tablename__ = "content_agent_uploads"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    uploaded_by_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    filename: Mapped[str] = mapped_column(String(255), nullable=False)
    checksum: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    row_count: Mapped[int] = mapped_column(Integer, nullable=False)
    schema_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    records: Mapped[list] = mapped_column(PortableJSON, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(TZDateTime, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=_utcnow, nullable=False)
    # v2 ownership fields
    rights_confirmed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    rights_confirmed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    uploader_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), nullable=True)

    def __repr__(self) -> str:
        return f"<ContentAgentUpload {self.filename} rows={self.row_count}>"


class ContentAgentJob(Base):
    __tablename__ = "content_agent_jobs"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    requested_by_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    upload_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("content_agent_uploads.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    status: Mapped[str] = mapped_column(
        String(32), default="queued", nullable=False, index=True
    )
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    revision: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    config: Mapped[dict] = mapped_column(PortableJSON, nullable=False)
    progress: Mapped[dict] = mapped_column(PortableJSON, default=dict, nullable=False)
    source_manifest: Mapped[list] = mapped_column(
        PortableJSON, default=list, nullable=False
    )
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
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=_utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        TZDateTime, default=_utcnow, onupdate=_utcnow, nullable=False
    )
    started_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)

    __table_args__ = (
        Index(
            "ix_content_agent_job_hash_revision",
            "request_hash",
            "revision",
            unique=True,
        ),
    )

    def __repr__(self) -> str:
        return f"<ContentAgentJob {self.id} status={self.status}>"


class LessonVocabularyItem(Base):
    __tablename__ = "lesson_vocabulary_items"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    lesson_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("lessons.id", ondelete="CASCADE"), nullable=False, index=True
    )
    vocabulary_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("vocabulary_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    source_job_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(),
        ForeignKey("content_agent_jobs.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    order_index: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=_utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint(
            "lesson_id", "vocabulary_id", name="uq_lesson_vocabulary_item"
        ),
        Index("ix_lesson_vocabulary_order", "lesson_id", "order_index"),
    )

    def __repr__(self) -> str:
        return f"<LessonVocabularyItem lesson={self.lesson_id} vocab={self.vocabulary_id}>"


class ContentProvenance(Base):
    __tablename__ = "content_provenance"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    job_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("content_agent_jobs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    entity_id: Mapped[uuid.UUID] = mapped_column(GUID(), nullable=False, index=True)
    source_name: Mapped[str] = mapped_column(String(100), nullable=False)
    source_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    # v1 backward-compatible fields (kept for existing rows)
    license_mode: Mapped[str] = mapped_column(String(64), nullable=False)
    source_checksum: Mapped[str | None] = mapped_column(String(64), nullable=True)
    is_generated: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    metadata_json: Mapped[dict] = mapped_column(
        "metadata", PortableJSON, default=dict, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=_utcnow, nullable=False)
    # v2 provenance fields (nullable — existing rows remain valid)
    source_version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    license_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    license_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    attribution_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw_checksum: Mapped[str | None] = mapped_column(String(64), nullable=True)
    record_checksum: Mapped[str | None] = mapped_column(String(64), nullable=True)
    lineage: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    content_usage: Mapped[str | None] = mapped_column(String(32), nullable=True)
    rights_confirmed_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    rights_statement_version: Mapped[str | None] = mapped_column(String(32), nullable=True)

    def __repr__(self) -> str:
        return f"<ContentProvenance {self.entity_type}/{self.entity_id}>"
