"""add lesson outcome (can-do statement) field

Revision ID: add_lesson_outcome
Revises: challenge_claim_unique
Create Date: 2026-08-03
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "add_lesson_outcome"
down_revision: str | None = "wallet_gems_non_negative"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("lessons", sa.Column("outcome", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("lessons", "outcome")
