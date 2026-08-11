"""add non-negative user wallet gems constraint

Revision ID: wallet_gems_non_negative
Revises: challenge_claim_unique
Create Date: 2026-08-02
"""

from collections.abc import Sequence

from alembic import op

revision: str = "wallet_gems_non_negative"
down_revision: str | None = "challenge_claim_unique"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_check_constraint(
        "ck_user_wallets_gems_non_negative",
        "user_wallets",
        "gems >= 0",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_user_wallets_gems_non_negative",
        "user_wallets",
        type_="check",
    )
