"""Add numeric_level and rank columns to users table

Revision ID: add_level_rank_system
Revises: add_proficiency_tables
Create Date: 2026-02-05 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'add_level_rank_system'
down_revision: Union[str, None] = 'add_proficiency_tables'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add numeric_level and rank columns to users table."""
    # Add numeric_level column with default value 1
    op.add_column('users', sa.Column('numeric_level', sa.Integer(), nullable=False, server_default='1'))
    
    # Add rank column with default value 'bronze'
    op.add_column('users', sa.Column('rank', sa.String(length=20), nullable=False, server_default='bronze'))
    
    # Update existing users to calculate their numeric_level based on total_xp
    # This is a simplified calculation - in production, use the proper formula
    op.execute("""
        UPDATE users 
        SET numeric_level = GREATEST(1, FLOOR(POWER(total_xp / 100.0, 0.666667)))
        WHERE total_xp > 0
    """)


def downgrade() -> None:
    """Remove numeric_level and rank columns from users table."""
    op.drop_column('users', 'rank')
    op.drop_column('users', 'numeric_level')
