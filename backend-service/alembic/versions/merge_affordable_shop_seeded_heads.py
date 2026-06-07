"""Merge affordable shop and seeded vocabulary heads.

Revision ID: merge_shop_seeded_heads
Revises: affordable_shop_avatars, c598efcaef97
Create Date: 2026-06-07
"""

from typing import Sequence, Union


# revision identifiers, used by Alembic.
revision: str = "merge_shop_seeded_heads"
down_revision: Union[str, tuple[str, str], None] = (
    "affordable_shop_avatars",
    "c598efcaef97",
)
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
