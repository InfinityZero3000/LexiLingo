"""Add affordable shop items, avatar catalog, and lesson bonus hints.

Revision ID: affordable_shop_avatars
Revises: add_fsrs_reminder_scheduler
"""

from typing import Sequence, Union
import json
import uuid

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID as PG_UUID, JSON as PG_JSON

from app.core.shop_catalog import SHOP_CATALOG


revision: str = "affordable_shop_avatars"
down_revision: Union[str, None] = "add_fsrs_reminder_scheduler"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "lesson_attempts",
        sa.Column(
            "bonus_hints",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
    )

    connection = op.get_bind()

    _insert = sa.text(
        "INSERT INTO shop_items (id, name, description, item_type, price_gems, "
        "effects, icon_url, is_available, created_at) VALUES "
        "(:id, :name, :description, :item_type, :price_gems, :effects, :icon_url, :is_available, NOW())"
    ).bindparams(
        sa.bindparam("id", type_=PG_UUID()),
        sa.bindparam("effects", type_=PG_JSON()),
    )

    _update = sa.text(
        "UPDATE shop_items SET description=:description, item_type=:item_type, "
        "price_gems=:price_gems, effects=:effects, icon_url=:icon_url, "
        "is_available=:is_available WHERE name=:name"
    ).bindparams(
        sa.bindparam("effects", type_=PG_JSON()),
    )

    for item in SHOP_CATALOG:
        existing = connection.execute(
            sa.text("SELECT name FROM shop_items WHERE name = :name"),
            {"name": item["name"]},
        ).first()
        params = {
            "name": item["name"],
            "description": item["description"],
            "item_type": item["item_type"],
            "price_gems": item["price_gems"],
            "effects": item.get("effects"),
            "icon_url": item.get("icon_url"),
            "is_available": item.get("is_available", True),
        }
        if existing:
            connection.execute(_update, params)
        else:
            connection.execute(_insert, {"id": uuid.uuid4(), **params})


def downgrade() -> None:
    avatar_names = [item["name"] for item in SHOP_CATALOG if item["item_type"] == "avatar"]
    connection = op.get_bind()
    shop_items = sa.table("shop_items", sa.column("name", sa.String()))
    connection.execute(shop_items.delete().where(shop_items.c.name.in_(avatar_names)))
    op.drop_column("lesson_attempts", "bonus_hints")
