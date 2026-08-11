"""Add per-user grammar spaced-repetition state.

Revision ID: f2c8a1d4e6b9
Revises: d7e1f4a9c2b3
Create Date: 2026-08-10
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from app.core.db_types import GUID, TZDateTime


revision: str = "f2c8a1d4e6b9"
down_revision: str = "d7e1f4a9c2b3"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_grammar_items",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column(
            "user_id",
            GUID(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "grammar_item_id",
            GUID(),
            sa.ForeignKey("grammar_items.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("ease_factor", sa.Float(), nullable=False),
        sa.Column("interval", sa.Integer(), nullable=False),
        sa.Column("repetitions", sa.Integer(), nullable=False),
        sa.Column("next_review_date", TZDateTime(), nullable=False),
        sa.Column("last_reviewed_at", TZDateTime(), nullable=True),
        sa.Column("fsrs_stability", sa.Float(), nullable=True),
        sa.Column("fsrs_difficulty", sa.Float(), nullable=True),
        sa.Column("fsrs_elapsed_days", sa.Integer(), nullable=True),
        sa.Column("fsrs_scheduled_days", sa.Integer(), nullable=True),
        sa.Column("fsrs_reps", sa.Integer(), nullable=True),
        sa.Column("fsrs_lapses", sa.Integer(), nullable=True),
        sa.Column("fsrs_state", sa.Integer(), nullable=True),
        sa.Column("fsrs_last_review", TZDateTime(), nullable=True),
        sa.Column("total_reviews", sa.Integer(), nullable=False),
        sa.Column("correct_reviews", sa.Integer(), nullable=False),
        sa.Column("added_at", TZDateTime(), nullable=False),
        sa.UniqueConstraint(
            "user_id",
            "grammar_item_id",
            name="uq_user_grammar_items_user_item",
        ),
    )
    op.create_index(
        "ix_user_grammar_items_user_id",
        "user_grammar_items",
        ["user_id"],
    )
    op.create_index(
        "ix_user_grammar_items_grammar_item_id",
        "user_grammar_items",
        ["grammar_item_id"],
    )
    op.create_index(
        "ix_user_grammar_items_next_review_date",
        "user_grammar_items",
        ["next_review_date"],
    )
    op.create_index(
        "ix_user_grammar_items_user_next_review",
        "user_grammar_items",
        ["user_id", "next_review_date"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_grammar_items_user_next_review",
        table_name="user_grammar_items",
    )
    op.drop_index(
        "ix_user_grammar_items_next_review_date",
        table_name="user_grammar_items",
    )
    op.drop_index(
        "ix_user_grammar_items_grammar_item_id",
        table_name="user_grammar_items",
    )
    op.drop_index(
        "ix_user_grammar_items_user_id",
        table_name="user_grammar_items",
    )
    op.drop_table("user_grammar_items")
