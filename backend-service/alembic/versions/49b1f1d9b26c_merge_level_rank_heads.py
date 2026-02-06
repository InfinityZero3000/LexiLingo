"""merge_level_rank_heads

Revision ID: 49b1f1d9b26c
Revises: add_level_rank_system, f3a8b2c9d4e5
Create Date: 2026-02-05 22:40:46.075257

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '49b1f1d9b26c'
down_revision: Union[str, None] = ('add_level_rank_system', 'f3a8b2c9d4e5')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
