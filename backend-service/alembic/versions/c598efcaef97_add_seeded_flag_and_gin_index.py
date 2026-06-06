"""add_seeded_flag_and_gin_index

Revision ID: c598efcaef97
Revises: add_fsrs_reminder_scheduler
Create Date: 2026-06-06 11:42:44.607318

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c598efcaef97'
down_revision: Union[str, None] = 'add_fsrs_reminder_scheduler'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Add column to users table
    op.add_column('users', sa.Column('has_seeded_basic_words', sa.Boolean(), server_default='false', nullable=False))
    
    # 2. Add GIN index for JSONB tags column on PostgreSQL
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        op.create_index(
            'ix_vocabulary_items_tags_gin',
            'vocabulary_items',
            ['tags'],
            unique=False,
            postgresql_using='gin'
        )


def downgrade() -> None:
    # 1. Drop GIN index if PostgreSQL
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        op.drop_index('ix_vocabulary_items_tags_gin', table_name='vocabulary_items')
        
    # 2. Drop column from users table
    op.drop_column('users', 'has_seeded_basic_words')
