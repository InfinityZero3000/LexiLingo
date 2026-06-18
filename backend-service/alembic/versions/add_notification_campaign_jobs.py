"""Add notification_campaign_jobs table.

Revision ID: add_notification_campaign_jobs
Revises: add_ranking_agent_jobs
Create Date: 2026-06-16
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.core.db_types import TZDateTime

revision: str = "add_notification_campaign_jobs"
down_revision: str = "add_ranking_agent_jobs"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "notification_campaign_jobs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "requested_by_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
            index=True,
        ),
        sa.Column("job_type", sa.String(32), nullable=False, index=True),
        sa.Column("status", sa.String(32), nullable=False, default="queued", index=True),
        sa.Column("progress", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("config", sa.JSON(), nullable=False),
        sa.Column("artifact", sa.JSON(), nullable=True),
        sa.Column("warnings", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("blocking_errors", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("delivery_stats", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("celery_task_id", sa.String(255), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("scheduled_at", TZDateTime(), nullable=True),
        sa.Column("started_at", TZDateTime(), nullable=True),
        sa.Column("completed_at", TZDateTime(), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, index=True),
        sa.Column("updated_at", TZDateTime(), nullable=False),
    )
    op.create_index(
        "ix_notification_campaign_type_status",
        "notification_campaign_jobs",
        ["job_type", "status"],
    )


def downgrade() -> None:
    op.drop_index("ix_notification_campaign_type_status", table_name="notification_campaign_jobs")
    op.drop_table("notification_campaign_jobs")
