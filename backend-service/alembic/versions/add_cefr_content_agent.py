"""Add durable CEFR content-agent workflow tables.

Revision ID: add_cefr_content_agent
Revises: a1b2c3d4e5f6, rebalance_basic_vocabulary
Create Date: 2026-06-15
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.core.db_types import TZDateTime

revision: str = "add_cefr_content_agent"
down_revision: tuple[str, str] = (
    "a1b2c3d4e5f6",
    "rebalance_basic_vocabulary",
)
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "content_agent_uploads",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("uploaded_by_id", sa.Uuid(), nullable=False),
        sa.Column("filename", sa.String(length=255), nullable=False),
        sa.Column("checksum", sa.String(length=64), nullable=False),
        sa.Column("row_count", sa.Integer(), nullable=False),
        sa.Column("schema_version", sa.Integer(), nullable=False),
        sa.Column("records", sa.JSON(), nullable=False),
        sa.Column("expires_at", TZDateTime(), nullable=False),
        sa.Column("created_at", TZDateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["uploaded_by_id"], ["users.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_content_agent_uploads_uploaded_by_id",
        "content_agent_uploads",
        ["uploaded_by_id"],
    )
    op.create_index(
        "ix_content_agent_uploads_checksum",
        "content_agent_uploads",
        ["checksum"],
    )
    op.create_index(
        "ix_content_agent_uploads_expires_at",
        "content_agent_uploads",
        ["expires_at"],
    )

    op.create_table(
        "content_agent_jobs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("requested_by_id", sa.Uuid(), nullable=True),
        sa.Column("upload_id", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("config", sa.JSON(), nullable=False),
        sa.Column("progress", sa.JSON(), nullable=False),
        sa.Column("source_manifest", sa.JSON(), nullable=False),
        sa.Column("artifact", sa.JSON(), nullable=True),
        sa.Column("warnings", sa.JSON(), nullable=False),
        sa.Column("blocking_errors", sa.JSON(), nullable=False),
        sa.Column("created_entity_ids", sa.JSON(), nullable=False),
        sa.Column("celery_task_id", sa.String(length=255), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False),
        sa.Column("updated_at", TZDateTime(), nullable=False),
        sa.Column("started_at", TZDateTime(), nullable=True),
        sa.Column("completed_at", TZDateTime(), nullable=True),
        sa.ForeignKeyConstraint(
            ["requested_by_id"], ["users.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["upload_id"], ["content_agent_uploads.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_content_agent_jobs_requested_by_id",
        "content_agent_jobs",
        ["requested_by_id"],
    )
    op.create_index(
        "ix_content_agent_jobs_upload_id", "content_agent_jobs", ["upload_id"]
    )
    op.create_index(
        "ix_content_agent_jobs_status", "content_agent_jobs", ["status"]
    )
    op.create_index(
        "ix_content_agent_jobs_request_hash",
        "content_agent_jobs",
        ["request_hash"],
    )
    op.create_index(
        "ix_content_agent_job_hash_revision",
        "content_agent_jobs",
        ["request_hash", "revision"],
        unique=True,
    )

    op.create_table(
        "lesson_vocabulary_items",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("lesson_id", sa.Uuid(), nullable=False),
        sa.Column("vocabulary_id", sa.Uuid(), nullable=False),
        sa.Column("source_job_id", sa.Uuid(), nullable=True),
        sa.Column("order_index", sa.Integer(), nullable=False),
        sa.Column("is_primary", sa.Boolean(), nullable=False),
        sa.Column("created_at", TZDateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["lesson_id"], ["lessons.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["source_job_id"], ["content_agent_jobs.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["vocabulary_id"], ["vocabulary_items.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "lesson_id", "vocabulary_id", name="uq_lesson_vocabulary_item"
        ),
    )
    op.create_index(
        "ix_lesson_vocabulary_items_lesson_id",
        "lesson_vocabulary_items",
        ["lesson_id"],
    )
    op.create_index(
        "ix_lesson_vocabulary_items_vocabulary_id",
        "lesson_vocabulary_items",
        ["vocabulary_id"],
    )
    op.create_index(
        "ix_lesson_vocabulary_items_source_job_id",
        "lesson_vocabulary_items",
        ["source_job_id"],
    )
    op.create_index(
        "ix_lesson_vocabulary_order",
        "lesson_vocabulary_items",
        ["lesson_id", "order_index"],
    )

    op.create_table(
        "content_provenance",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("job_id", sa.Uuid(), nullable=False),
        sa.Column("entity_type", sa.String(length=50), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=False),
        sa.Column("source_name", sa.String(length=100), nullable=False),
        sa.Column("source_url", sa.String(length=1000), nullable=True),
        sa.Column("license_mode", sa.String(length=64), nullable=False),
        sa.Column("source_checksum", sa.String(length=64), nullable=True),
        sa.Column("is_generated", sa.Boolean(), nullable=False),
        sa.Column("metadata", sa.JSON(), nullable=False),
        sa.Column("created_at", TZDateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["job_id"], ["content_agent_jobs.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_content_provenance_job_id", "content_provenance", ["job_id"]
    )
    op.create_index(
        "ix_content_provenance_entity_type",
        "content_provenance",
        ["entity_type"],
    )
    op.create_index(
        "ix_content_provenance_entity_id",
        "content_provenance",
        ["entity_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_content_provenance_entity_id", table_name="content_provenance")
    op.drop_index("ix_content_provenance_entity_type", table_name="content_provenance")
    op.drop_index("ix_content_provenance_job_id", table_name="content_provenance")
    op.drop_table("content_provenance")
    op.drop_index(
        "ix_lesson_vocabulary_order", table_name="lesson_vocabulary_items"
    )
    op.drop_index(
        "ix_lesson_vocabulary_items_source_job_id",
        table_name="lesson_vocabulary_items",
    )
    op.drop_index(
        "ix_lesson_vocabulary_items_vocabulary_id",
        table_name="lesson_vocabulary_items",
    )
    op.drop_index(
        "ix_lesson_vocabulary_items_lesson_id",
        table_name="lesson_vocabulary_items",
    )
    op.drop_table("lesson_vocabulary_items")
    op.drop_index(
        "ix_content_agent_job_hash_revision", table_name="content_agent_jobs"
    )
    op.drop_index(
        "ix_content_agent_jobs_request_hash", table_name="content_agent_jobs"
    )
    op.drop_index("ix_content_agent_jobs_status", table_name="content_agent_jobs")
    op.drop_index("ix_content_agent_jobs_upload_id", table_name="content_agent_jobs")
    op.drop_index(
        "ix_content_agent_jobs_requested_by_id", table_name="content_agent_jobs"
    )
    op.drop_table("content_agent_jobs")
    op.drop_index(
        "ix_content_agent_uploads_expires_at",
        table_name="content_agent_uploads",
    )
    op.drop_index(
        "ix_content_agent_uploads_checksum", table_name="content_agent_uploads"
    )
    op.drop_index(
        "ix_content_agent_uploads_uploaded_by_id",
        table_name="content_agent_uploads",
    )
    op.drop_table("content_agent_uploads")
