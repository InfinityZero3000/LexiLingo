"""Add unique constraint for leaderboard user/week rows

Revision ID: 8d1e6a2f4c11
Revises: add_onboarding_completed_flag
Create Date: 2026-04-15
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "8d1e6a2f4c11"
down_revision: Union[str, None] = "add_onboarding_completed_flag"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_unique_constraint(
        "uq_leaderboard_user_week",
        "leaderboard_entries",
        ["user_id", "week_start"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_leaderboard_user_week",
        "leaderboard_entries",
        type_="unique",
    )
