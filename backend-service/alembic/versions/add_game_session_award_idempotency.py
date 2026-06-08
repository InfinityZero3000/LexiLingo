"""Add database idempotency for XP source references.

Revision ID: game_award_idempotency
Revises: merge_shop_seeded_heads
Create Date: 2026-06-07
"""

from typing import Sequence, Union

from alembic import op


revision: str = "game_award_idempotency"
down_revision: Union[str, None] = "merge_shop_seeded_heads"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS
            uq_xp_transactions_user_source_ref
        ON xp_transactions (user_id, source, source_id)
        WHERE source_id IS NOT NULL
        """
    )


def downgrade() -> None:
    op.execute(
        "DROP INDEX IF EXISTS uq_xp_transactions_user_source_ref"
    )
