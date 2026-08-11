"""add product events

Revision ID: add_product_events
Revises: f2c8a1d4e6b9
Create Date: 2026-08-10

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.core.db_types import GUID, PortableJSON, TZDateTime

revision: str = "add_product_events"
down_revision: str | None = "f2c8a1d4e6b9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "product_events",
        sa.Column("id", GUID(), nullable=False),
        sa.Column("event_id", GUID(), nullable=False),
        sa.Column("user_id", GUID(), nullable=False),
        sa.Column("event_name", sa.String(length=100), nullable=False),
        sa.Column("properties", PortableJSON(), nullable=False, server_default=sa.text("'{}'")),
        sa.Column("source", sa.String(length=50), nullable=False),
        sa.Column("client_timestamp", TZDateTime(), nullable=False),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "event_id", name="uq_product_events_user_event"),
    )
    op.create_index(
        "ix_product_events_event_created",
        "product_events",
        ["event_name", "created_at"],
    )
    op.create_index(
        "ix_product_events_user_created",
        "product_events",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_product_events_user_created", table_name="product_events")
    op.drop_index("ix_product_events_event_created", table_name="product_events")
    op.drop_table("product_events")
