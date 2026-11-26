"""add the 'test' role for accounts that are not real learners

Revision ID: e3b9c6a2f417
Revises: d7a2f5c1e9b3
Create Date: 2026-11-26 10:00:00.000000

Same privileges as 'user' (level 0); the slug is what tells a test account
apart in the admin list and in queries.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e3b9c6a2f417"
down_revision: Union[str, None] = "d7a2f5c1e9b3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_TEST_ROLE_ID = "00000000-0000-0000-0000-000000000004"


def upgrade() -> None:
    op.get_bind().execute(
        sa.text(
            "INSERT INTO roles (id, name, slug, description, level, is_system, is_active, created_at, updated_at) "
            "VALUES (:id, 'Test', 'test', 'Test account, not a real learner', 0, true, true, now(), now()) "
            "ON CONFLICT (slug) DO NOTHING"
        ),
        {"id": _TEST_ROLE_ID},
    )


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(
        sa.text(
            "UPDATE users SET role_id = (SELECT id FROM roles WHERE slug = 'user') "
            "WHERE role_id IN (SELECT id FROM roles WHERE slug = 'test')"
        )
    )
    bind.execute(sa.text("DELETE FROM roles WHERE slug = 'test'"))
