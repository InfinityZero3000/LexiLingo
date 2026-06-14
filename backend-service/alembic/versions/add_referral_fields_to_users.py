"""Add referral_code and referred_by to users table.

Revision ID: a1b2c3d4e5f6
Revises: f3a8b2c9d4e5
Create Date: 2026-06-14

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "a1b2c3d4e5f6"
down_revision = "f3a8b2c9d4e5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("referral_code", sa.String(12), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("referred_by", sa.Uuid(), nullable=True),
    )
    op.create_unique_constraint("uq_users_referral_code", "users", ["referral_code"])
    op.create_index("ix_users_referral_code", "users", ["referral_code"])
    op.create_foreign_key(
        "fk_users_referred_by",
        "users",
        "users",
        ["referred_by"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_users_referred_by", "users", type_="foreignkey")
    op.drop_index("ix_users_referral_code", "users")
    op.drop_constraint("uq_users_referral_code", "users", type_="unique")
    op.drop_column("users", "referred_by")
    op.drop_column("users", "referral_code")
