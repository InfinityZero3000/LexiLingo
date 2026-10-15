"""Add per-day skill rollup so exercise_attempts can be pruned.

exercise_attempts holds one row per answer, is never read back, and has no
retention policy — roughly 400 bytes each, so an active learner adds megabytes
a year and the table only grows. This rollup keeps the same information at the
resolution anything actually needs, bounded by days-with-activity rather than
by how much someone practised in a day.

Revision ID: c3f8a2d5e714
Revises: b7c4e9a1d2f8
Create Date: 2026-08-17
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from app.core.db_types import GUID


revision: str = "c3f8a2d5e714"
down_revision: str = "b7c4e9a1d2f8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# The skilltype enum already exists (user_skill_scores, exercise_attempts).
# postgresql.ENUM is what honours create_type=False; plain sa.Enum ignores it
# and tries to CREATE TYPE again.
_SKILL_ENUM = postgresql.ENUM(
    "VOCABULARY",
    "GRAMMAR",
    "READING",
    "LISTENING",
    "SPEAKING",
    "WRITING",
    name="skilltype",
    create_type=False,
)


def upgrade() -> None:
    op.create_table(
        "skill_daily_stats",
        sa.Column(
            "user_id",
            GUID(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("day", sa.Date(), primary_key=True),
        sa.Column("skill", _SKILL_ENUM, primary_key=True),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("correct", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("score_sum", sa.Float(), nullable=False, server_default="0"),
        sa.Column("difficulty_sum", sa.Float(), nullable=False, server_default="0"),
    )
    # Pruning and per-learner history both scan by user and date.
    op.create_index(
        "ix_skill_daily_stats_user_day", "skill_daily_stats", ["user_id", "day"]
    )


def downgrade() -> None:
    op.drop_index("ix_skill_daily_stats_user_day", table_name="skill_daily_stats")
    op.drop_table("skill_daily_stats")
