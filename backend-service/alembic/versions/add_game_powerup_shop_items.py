"""Add in-game power-up shop items (time freeze, skip token, shield, etc).

Revision ID: add_game_powerup_items
Revises: backfill_verified_users
"""

from typing import Sequence, Union
import uuid

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID as PG_UUID, JSON as PG_JSON


revision: str = "add_game_powerup_items"
down_revision: Union[str, None] = "backfill_verified_users"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


GAME_POWERUP_ITEMS: tuple[dict, ...] = (
    {
        "name": "Time Freeze",
        "description": "Pause the countdown timer for 10 seconds in any timed game",
        "item_type": "time_freeze",
        "price_gems": 10,
        "effects": {"seconds": 10},
        "is_available": True,
    },
    {
        "name": "Extra Time",
        "description": "Add 20 seconds straight to the clock in any timed game",
        "item_type": "extra_time",
        "price_gems": 15,
        "effects": {"seconds": 20},
        "is_available": True,
    },
    {
        "name": "Skip Token",
        "description": "Skip the current word or question with no penalty",
        "item_type": "skip_token",
        "price_gems": 12,
        "effects": {},
        "is_available": True,
    },
    {
        "name": "Magnifying Glass",
        "description": "Free reveal: the next letter, or eliminate 2 wrong options",
        "item_type": "reveal_hint",
        "price_gems": 8,
        "effects": {"mode": "letter"},
        "is_available": True,
    },
    {
        "name": "Quick Translate",
        "description": "Reveal the Vietnamese translation of the current word",
        "item_type": "translate_hint",
        "price_gems": 8,
        "effects": {"mode": "translation"},
        "is_available": True,
    },
    {
        "name": "Shield",
        "description": "Negate the next wrong answer or life loss",
        "item_type": "mistake_shield",
        "price_gems": 18,
        "effects": {},
        "is_available": True,
    },
    {
        "name": "Extra Heart",
        "description": "Start Hangman with one extra life",
        "item_type": "extra_heart",
        "price_gems": 15,
        "effects": {"lives": 1},
        "is_available": True,
    },
    {
        "name": "Lucky Clover",
        "description": "30% chance to auto-correct your next wrong answer",
        "item_type": "lucky_clover",
        "price_gems": 20,
        "effects": {"chance": 0.3},
        "is_available": True,
    },
    {
        "name": "Score Multiplier",
        "description": "Double your in-game score for the rest of this session",
        "item_type": "score_multiplier",
        "price_gems": 22,
        "effects": {"multiplier": 2},
        "is_available": True,
    },
    {
        "name": "Pair Swap",
        "description": "Undo one wrong match in Matching Game for a free retry",
        "item_type": "pair_swap",
        "price_gems": 10,
        "effects": {},
        "is_available": True,
    },
)


def upgrade() -> None:
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

    for item in GAME_POWERUP_ITEMS:
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
    powerup_names = [item["name"] for item in GAME_POWERUP_ITEMS]
    connection = op.get_bind()
    shop_items = sa.table("shop_items", sa.column("name", sa.String()))
    connection.execute(shop_items.delete().where(shop_items.c.name.in_(powerup_names)))
