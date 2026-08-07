"""merge notification-campaign and streak-restore heads

Revision ID: f70a61a5ce3d
Revises: add_notification_campaign_jobs, bd41c2120a87
Create Date: 2026-08-08 00:38:07.815654

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f70a61a5ce3d'
down_revision: Union[str, None] = ('add_notification_campaign_jobs', 'bd41c2120a87')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
