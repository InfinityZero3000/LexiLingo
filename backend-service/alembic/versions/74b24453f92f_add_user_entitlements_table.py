"""add user entitlements table

Revision ID: 74b24453f92f
Revises: add_partner_api_keys
Create Date: 2026-08-08 00:42:22.630820

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.core.db_types import GUID, TZDateTime


# revision identifiers, used by Alembic.
revision: str = '74b24453f92f'
down_revision: Union[str, None] = 'add_partner_api_keys'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_entitlements",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("entitlement_id", sa.String(length=100), nullable=False),
        sa.Column("product_id", sa.String(length=200), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("expires_at", TZDateTime(), nullable=True),
        sa.Column("source", sa.String(length=20), nullable=False),
        sa.Column("synced_at", TZDateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "entitlement_id",
            name="uq_user_entitlement_user_entitlement",
        ),
    )
    op.create_index(
        "ix_user_entitlements_user_id",
        "user_entitlements",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_entitlements_user_id",
        table_name="user_entitlements",
    )
    op.drop_table("user_entitlements")
