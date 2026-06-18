"""Add ranking_agent_jobs table.

Revision ID: add_ranking_agent_jobs
Revises: add_content_provenance_v2
Create Date: 2026-06-15
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.core.db_types import TZDateTime

revision: str = "add_ranking_agent_jobs"
down_revision: str = "add_content_provenance_v2"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "ranking_agent_jobs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "requested_by_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("job_type", sa.String(32), nullable=False),
        sa.Column("status", sa.String(32), nullable=False, server_default="queued"),
        sa.Column("progress", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("config", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("artifact", sa.JSON(), nullable=True),
        sa.Column("warnings", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("blocking_errors", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("created_entity_ids", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("celery_task_id", sa.String(255), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", TZDateTime, nullable=False),
        sa.Column("updated_at", TZDateTime, nullable=False),
        sa.Column("started_at", TZDateTime, nullable=True),
        sa.Column("completed_at", TZDateTime, nullable=True),
    )
    op.create_index(
        "ix_ranking_agent_jobs_requested_by_id",
        "ranking_agent_jobs",
        ["requested_by_id"],
    )
    op.create_index(
        "ix_ranking_agent_jobs_status",
        "ranking_agent_jobs",
        ["status"],
    )
    op.create_index(
        "ix_ranking_agent_jobs_created_at",
        "ranking_agent_jobs",
        ["created_at"],
    )
    op.create_index(
        "ix_ranking_agent_job_type_status",
        "ranking_agent_jobs",
        ["job_type", "status"],
    )


def downgrade() -> None:
    op.drop_table("ranking_agent_jobs")
