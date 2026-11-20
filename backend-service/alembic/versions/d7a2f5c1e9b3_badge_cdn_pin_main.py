"""repoint badge CDN URLs from the deleted @feature branch to @main

Revision ID: d7a2f5c1e9b3
Revises: c4e8a1b7d3f6
Create Date: 2026-11-20 09:00:00.000000

fix_badge_cdn_urls did this once, but scripts/backfill_achievements.py wrote
@feature again, so 44 of 48 production rows 404 on jsDelivr.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d7a2f5c1e9b3"
down_revision: Union[str, None] = "c4e8a1b7d3f6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_REPO = "https://cdn.jsdelivr.net/gh/InfinityZero3000/LexiLingo"


def _swap(old: str, new: str) -> None:
    op.get_bind().execute(
        sa.text(
            "UPDATE achievements SET badge_icon = replace(badge_icon, :old, :new) "
            "WHERE badge_icon LIKE :like"
        ),
        {"old": f"{_REPO}@{old}/", "new": f"{_REPO}@{new}/", "like": f"{_REPO}@{old}/%"},
    )


def upgrade() -> None:
    _swap("feature", "main")


def downgrade() -> None:
    # The old pin points at a branch that no longer exists; nothing to restore.
    pass
