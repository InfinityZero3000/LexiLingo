"""level_exam_attempts: sittings of the CEFR promotion exam

Revision ID: c4d6e8f0a123
Revises: b2c4d6e8f012
Create Date: 2026-11-15
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "c4d6e8f0a123"
down_revision: str | None = "b2c4d6e8f012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "level_exam_attempts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("from_level", sa.String(5), nullable=False),
        sa.Column("sections", postgresql.JSONB(), nullable=False),
        sa.Column("answers", postgresql.JSONB(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="in_progress"),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("result_level", sa.String(5), nullable=True),
        sa.Column("section_scores", postgresql.JSONB(), nullable=True),
        sa.Column("score", sa.Float(), nullable=True),
        sa.CheckConstraint(
            "status IN ('in_progress', 'submitted', 'expired')",
            name="ck_level_exam_attempts_status",
        ),
    )
    op.create_index(
        "ix_level_exam_attempts_user_started",
        "level_exam_attempts",
        ["user_id", "started_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_level_exam_attempts_user_started", table_name="level_exam_attempts")
    op.drop_table("level_exam_attempts")
