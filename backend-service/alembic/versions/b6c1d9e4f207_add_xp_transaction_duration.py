"""add xp_transactions.duration_seconds

Minute-based daily quests ("watch 20 minutes of video") need the duration of an
activity to survive the request that reported it. XPTransaction is already
written once per award and deduped on (user_id, source, source_id), so the
duration belongs on that row rather than in a second table.

Revision ID: b6c1d9e4f207
Revises: 4a7b1c9e2d30
Create Date: 2026-10-01
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b6c1d9e4f207"
down_revision: Union[str, None] = "4a7b1c9e2d30"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, None] = None

_TABLE = "xp_transactions"
_COLUMN = "duration_seconds"


def _has_column() -> bool:
    inspector = sa.inspect(op.get_bind())
    if _TABLE not in inspector.get_table_names():
        return False
    return any(c["name"] == _COLUMN for c in inspector.get_columns(_TABLE))


def upgrade() -> None:
    if not _has_column():
        op.add_column(_TABLE, sa.Column(_COLUMN, sa.Integer(), nullable=True))


def downgrade() -> None:
    if _has_column():
        op.drop_column(_TABLE, _COLUMN)
