"""users.lexi_reply_language: which language Lexi explains in

Revision ID: b3d5f7a9c1e2
Revises: a7c1e3f5b902
Create Date: 2026-11-16
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "b3d5f7a9c1e2"
down_revision: str | None = "a7c1e3f5b902"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # "app" is what every learner already gets, so existing rows keep their behaviour.
    op.add_column(
        "users",
        sa.Column("lexi_reply_language", sa.String(10), nullable=False, server_default="app"),
    )
    op.create_check_constraint(
        "ck_users_lexi_reply_language",
        "users",
        "lexi_reply_language IN ('app', 'native')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_users_lexi_reply_language", "users", type_="check")
    op.drop_column("users", "lexi_reply_language")
