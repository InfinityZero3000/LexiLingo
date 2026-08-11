"""merge notification campaign and streak restore heads

Revision ID: 0d7ae4e272b7
Revises: add_notification_campaign_jobs, bd41c2120a87
Create Date: 2026-06-19 19:07:52.873150

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0d7ae4e272b7'
down_revision: Union[str, None] = ('add_notification_campaign_jobs', 'bd41c2120a87')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
