"""Add goal/interest onboarding preferences to users

Revision ID: add_user_goal_interest
Revises: idx_users_active_rank
Create Date: 2026-08-07
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "add_user_goal_interest"
down_revision: Union[str, None] = "idx_users_active_rank"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("goal", sa.String(length=30), nullable=True))
    op.add_column("users", sa.Column("interest", sa.String(length=30), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "interest")
    op.drop_column("users", "goal")
