"""Add idempotent new-user starter rewards.

Revision ID: new_user_starter_reward
Revises: game_award_idempotency
Create Date: 2026-06-07
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.core.db_types import GUID, TZDateTime


revision: str = "new_user_starter_reward"
down_revision: Union[str, None] = "game_award_idempotency"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_reward_grants",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("reward_key", sa.String(length=100), nullable=False),
        sa.Column("gems_awarded", sa.Integer(), nullable=False),
        sa.Column("created_at", TZDateTime(), nullable=False),
        sa.Column("popup_seen_at", TZDateTime(), nullable=True),
        sa.Column("push_sent_at", TZDateTime(), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "reward_key",
            name="uq_user_reward_grant_user_key",
        ),
    )
    op.create_index(
        "ix_user_reward_grants_user_id",
        "user_reward_grants",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_reward_grants_user_id",
        table_name="user_reward_grants",
    )
    op.drop_table("user_reward_grants")
