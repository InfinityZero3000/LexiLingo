"""merge grammar-fsrs and entitlements heads

Revision ID: 7364c510b147
Revises: f2c8a1d4e6b9, 74b24453f92f
Create Date: 2026-08-11 07:05:29.539421

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7364c510b147'
down_revision: Union[str, None] = ('f2c8a1d4e6b9', '74b24453f92f')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
