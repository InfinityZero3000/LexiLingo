"""Add cached rank score fields to users

Revision ID: add_user_rank_score_cache
Revises: 8d1e6a2f4c11
Create Date: 2026-05-22
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "add_user_rank_score_cache"
down_revision: Union[str, None] = "8d1e6a2f4c11"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("rank_score", sa.Float(), nullable=False, server_default="0"),
    )
    op.add_column(
        "users",
        sa.Column("rank_level_score", sa.Float(), nullable=False, server_default="0"),
    )
    op.add_column(
        "users",
        sa.Column(
            "rank_proficiency_score",
            sa.Float(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "rank_proficiency_score")
    op.drop_column("users", "rank_level_score")
    op.drop_column("users", "rank_score")
