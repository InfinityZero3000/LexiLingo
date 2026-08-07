"""Add composite index on users(is_active, rank) for leaderboard queries

Revision ID: a1b2c3d4e5f6
Revises: backfill_vocab_lcs
Create Date: 2026-08-06
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "idx_users_active_rank"
down_revision: Union[str, None] = "backfill_vocab_lcs"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Every leaderboard read filters users on `is_active = true AND lower(rank) = :league`
    # with no supporting index — a full table scan on `users` on every uncached request.
    op.create_index(
        "idx_users_active_rank",
        "users",
        ["is_active", "rank"],
    )


def downgrade() -> None:
    op.drop_index("idx_users_active_rank", table_name="users")
