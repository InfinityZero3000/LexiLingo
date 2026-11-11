"""add placement floor to proficiency profile

A formal test result is the lowest level the activity-based recalculation may
report; without it the next lesson recomputes the level from counts and erases
the test.

Revision ID: e3f5a7b9c012
Revises: d8e2a4f6c901
Create Date: 2026-10-28
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "e3f5a7b9c012"
down_revision: str | None = "d8e2a4f6c901"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "user_proficiency_profiles", sa.Column("placement_level", sa.String(5), nullable=True)
    )
    op.add_column(
        "user_proficiency_profiles",
        sa.Column("placement_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user_proficiency_profiles", "placement_at")
    op.drop_column("user_proficiency_profiles", "placement_level")
