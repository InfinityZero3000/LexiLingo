"""Add affordable shop items, avatar catalog, and lesson bonus hints.

Revision ID: affordable_shop_avatars
Revises: add_fsrs_reminder_scheduler
"""

from typing import Sequence, Union
import uuid

from alembic import op
import sqlalchemy as sa

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
    shop_items = sa.table(
        "shop_items",
        sa.column("id", sa.String()),
        sa.column("name", sa.String()),
        sa.column("description", sa.Text()),
        sa.column("item_type", sa.String()),
        sa.column("price_gems", sa.Integer()),
        sa.column("effects", sa.JSON()),
        sa.column("icon_url", sa.String()),
        sa.column("is_available", sa.Boolean()),
    )

    for item in SHOP_CATALOG:
        existing = connection.execute(
            sa.select(shop_items.c.name).where(shop_items.c.name == item["name"])
        ).first()
        values = {
            "description": item["description"],
            "item_type": item["item_type"],
            "price_gems": item["price_gems"],
            "effects": item.get("effects"),
            "icon_url": item.get("icon_url"),
            "is_available": item.get("is_available", True),
        }
        if existing:
            connection.execute(
                shop_items.update()
                .where(shop_items.c.name == item["name"])
                .values(**values)
            )
        else:
            connection.execute(
                shop_items.insert().values(
                    id=str(uuid.uuid4()),
                    name=item["name"],
                    **values,
                )
            )


def downgrade() -> None:
    avatar_names = [item["name"] for item in SHOP_CATALOG if item["item_type"] == "avatar"]
    connection = op.get_bind()
    shop_items = sa.table("shop_items", sa.column("name", sa.String()))
    connection.execute(shop_items.delete().where(shop_items.c.name.in_(avatar_names)))
    op.drop_column("lesson_attempts", "bonus_hints")
