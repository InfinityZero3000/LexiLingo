"""add banners table

In-app promo banners (hero/sidebar/interstitial) that admins schedule and
target by CEFR level range and learner language. Replaces the "Coming Soon"
admin stub with a real, admin-managed CRUD surface.

Revision ID: d8e2a4f6c901
Revises: b6c1d9e4f207
Create Date: 2026-10-07
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from app.core.db_types import GUID

revision: str = "d8e2a4f6c901"
down_revision: str | None = "b6c1d9e4f207"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "banners",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("image_url", sa.String(1000), nullable=False),
        sa.Column("link_url", sa.String(1000), nullable=True),
        sa.Column("position", sa.String(20), nullable=False, server_default="hero"),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("end_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("target_min_level", sa.String(10), nullable=True),
        sa.Column("target_max_level", sa.String(10), nullable=True),
        sa.Column("target_language", sa.String(10), nullable=True),
        sa.Column(
            "created_by_id", GUID(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
        ),
    )
    op.create_index(
        "ix_banners_active_position_priority",
        "banners",
        ["is_active", "position", "priority"],
    )


def downgrade() -> None:
    op.drop_index("ix_banners_active_position_priority", table_name="banners")
    op.drop_table("banners")
