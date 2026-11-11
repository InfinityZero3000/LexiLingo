"""add app_settings and admin_gem_grants

Revision ID: f4a6b8c0d123
Revises: e3f5a7b9c012
Create Date: 2026-11-10
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "f4a6b8c0d123"
down_revision: str | None = "e3f5a7b9c012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "app_settings",
        sa.Column("key", sa.String(100), primary_key=True),
        sa.Column("value", postgresql.JSONB(), nullable=False),
        sa.Column("updated_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "admin_gem_grants",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("actor_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("kind", sa.String(10), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(300), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_admin_gem_grants_actor_created", "admin_gem_grants", ["actor_id", "created_at"])
    op.create_index("ix_admin_gem_grants_user_id", "admin_gem_grants", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_admin_gem_grants_user_id", table_name="admin_gem_grants")
    op.drop_index("ix_admin_gem_grants_actor_created", table_name="admin_gem_grants")
    op.drop_table("admin_gem_grants")
    op.drop_table("app_settings")
