"""Add FSRS fields for vocabulary speaking practice

Revision ID: add_fsrs_and_speaking_fields
Revises: add_user_rank_score_cache
Create Date: 2026-05-25
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "add_fsrs_and_speaking_fields"
down_revision: Union[str, None] = "add_user_rank_score_cache"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_stability", sa.Float(), nullable=True, server_default="0"),
    )
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_difficulty", sa.Float(), nullable=True, server_default="0"),
    )
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_elapsed_days", sa.Integer(), nullable=True, server_default="0"),
    )
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_scheduled_days", sa.Integer(), nullable=True, server_default="0"),
    )
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_reps", sa.Integer(), nullable=True, server_default="0"),
    )
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_lapses", sa.Integer(), nullable=True, server_default="0"),
    )
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_state", sa.Integer(), nullable=True, server_default="0"),
    )
    op.add_column(
        "user_vocabulary",
        sa.Column("fsrs_last_review", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user_vocabulary", "fsrs_last_review")
    op.drop_column("user_vocabulary", "fsrs_state")
    op.drop_column("user_vocabulary", "fsrs_lapses")
    op.drop_column("user_vocabulary", "fsrs_reps")
    op.drop_column("user_vocabulary", "fsrs_scheduled_days")
    op.drop_column("user_vocabulary", "fsrs_elapsed_days")
    op.drop_column("user_vocabulary", "fsrs_difficulty")
    op.drop_column("user_vocabulary", "fsrs_stability")
