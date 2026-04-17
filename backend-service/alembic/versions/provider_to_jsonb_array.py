"""Convert users.provider from VARCHAR to JSONB array

Allows a single account to be linked to multiple auth providers (e.g. local + google).

Revision ID: provider_to_jsonb_array
Revises: add_admin_content_and_seed_roles
Create Date: 2026-03-13 07:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB


revision: str = 'provider_to_jsonb_array'
down_revision: Union[str, None] = 'add_admin_content_and_seed_roles'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Convert provider VARCHAR(20) → JSONB array.

    'local'  → ["local"]
    'google' → ["google"]
    etc.
    """
    op.execute("""
        ALTER TABLE users
        ALTER COLUMN provider TYPE JSONB
        USING jsonb_build_array(provider)
    """)
    op.execute("""
        ALTER TABLE users
        ALTER COLUMN provider SET DEFAULT '["local"]'::jsonb
    """)
    # Back-fill any NULLs that may exist
    op.execute("""
        UPDATE users SET provider = '["local"]'::jsonb WHERE provider IS NULL
    """)


def downgrade() -> None:
    """Convert JSONB array back to VARCHAR — takes first element."""
    op.execute("""
        ALTER TABLE users
        ALTER COLUMN provider TYPE VARCHAR(20)
        USING (provider->>0)
    """)
    op.execute("""
        ALTER TABLE users
        ALTER COLUMN provider SET DEFAULT 'local'
    """)
    op.execute("""
        UPDATE users SET provider = 'local' WHERE provider IS NULL
    """)
