"""Add explicit skill labels to courses and lessons.

Completion used to guess which of the six CEFR skills a lesson exercised by
keyword-matching the course's free-form tags, defaulting to "vocabulary" when
nothing matched. Listening, speaking, reading and writing were therefore
almost never credited. These columns carry the label instead.

Nullable on purpose: existing rows keep the tag-based guess as a fallback
until scripts/backfill_content_skill.py labels them.

Revision ID: b7c4e9a1d2f8
Revises: add_product_events
Create Date: 2026-08-16
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "b7c4e9a1d2f8"
down_revision: str = "add_product_events"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("courses", sa.Column("skill", sa.String(length=20), nullable=True))
    op.add_column("lessons", sa.Column("skill", sa.String(length=20), nullable=True))


def downgrade() -> None:
    op.drop_column("lessons", "skill")
    op.drop_column("courses", "skill")
