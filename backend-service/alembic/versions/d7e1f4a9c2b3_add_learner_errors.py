"""Add durable learner error history.

Revision ID: d7e1f4a9c2b3
Revises: add_notification_campaign_jobs, bd41c2120a87
Create Date: 2026-08-10
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from app.core.db_types import GUID, PortableJSON, TZDateTime


revision: str = "d7e1f4a9c2b3"
down_revision: tuple[str, str] = (
    "add_notification_campaign_jobs",
    "bd41c2120a87",
)
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "learner_errors",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column(
            "user_id",
            GUID(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("skill", sa.String(length=50), nullable=True),
        sa.Column("error_type", sa.String(length=100), nullable=True),
        sa.Column("submitted_answer", sa.Text(), nullable=True),
        sa.Column("correct_answer", sa.Text(), nullable=True),
        sa.Column("context", PortableJSON(), nullable=True),
        sa.Column(
            "created_at",
            TZDateTime(),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("ix_learner_errors_user_id", "learner_errors", ["user_id"])
    op.create_index("ix_learner_errors_source", "learner_errors", ["source"])
    op.create_index(
        "ix_learner_errors_user_source",
        "learner_errors",
        ["user_id", "source"],
    )


def downgrade() -> None:
    op.drop_index("ix_learner_errors_user_source", table_name="learner_errors")
    op.drop_index("ix_learner_errors_source", table_name="learner_errors")
    op.drop_index("ix_learner_errors_user_id", table_name="learner_errors")
    op.drop_table("learner_errors")
