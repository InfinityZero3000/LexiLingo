"""Add onboarding completion flag to users

Revision ID: add_onboarding_completed_flag
Revises: provider_to_jsonb_array
Create Date: 2026-04-03
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "add_onboarding_completed_flag"
down_revision: Union[str, None] = "provider_to_jsonb_array"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "is_onboarding_completed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )

    # Backfill likely existing users who already progressed beyond first-time state.
    op.execute(
        """
        UPDATE users
        SET is_onboarding_completed = TRUE
        WHERE total_xp > 0
           OR UPPER(COALESCE(level, 'A1')) <> 'A1'
        """
    )


def downgrade() -> None:
    op.drop_column("users", "is_onboarding_completed")
