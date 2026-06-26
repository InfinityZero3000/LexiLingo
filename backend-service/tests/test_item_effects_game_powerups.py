"""Tests for the generic instant-consumable handler covering game power-up items."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.shop_catalog import GAME_POWERUP_ITEM_TYPES
from app.models.gamification import ShopItem, UserInventory
from app.models.user import User
from app.services.item_effects_service import ItemEffectsService


async def _give_item(
    db_session: AsyncSession,
    user: User,
    item_type: str,
    effects: dict,
    quantity: int = 1,
) -> UserInventory:
    shop_item = ShopItem(
        name=f"Test {item_type}",
        description="test item",
        item_type=item_type,
        price_gems=10,
        effects=effects,
        is_available=True,
    )
    db_session.add(shop_item)
    await db_session.flush()

    inventory = UserInventory(
        user_id=user.id,
        shop_item_id=shop_item.id,
        quantity=quantity,
    )
    db_session.add(inventory)
    await db_session.commit()
    return inventory


@pytest.mark.asyncio
@pytest.mark.parametrize("item_type", GAME_POWERUP_ITEM_TYPES)
async def test_instant_game_powerup_consumes_one_and_echoes_effects(
    db_session: AsyncSession,
    test_user: User,
    item_type: str,
):
    effects = {"seconds": 10} if "time" in item_type else {"chance": 0.3}
    inventory = await _give_item(db_session, test_user, item_type, effects, quantity=2)

    service = ItemEffectsService(db_session)
    success, message, applied_effects = await service.use_item(test_user.id, inventory.id)

    assert success is True
    assert message
    assert applied_effects["item_type"] == item_type
    for key, value in effects.items():
        assert applied_effects[key] == value

    await db_session.refresh(inventory)
    assert inventory.quantity == 1
    # Instant power-ups have no duration_hours, so they never become a
    # timed "active boost" like double_xp does.
    assert inventory.is_active is False
    assert inventory.expires_at is None


@pytest.mark.asyncio
async def test_instant_game_powerup_rejects_when_out_of_stock(
    db_session: AsyncSession,
    test_user: User,
):
    inventory = await _give_item(db_session, test_user, "skip_token", {}, quantity=0)

    service = ItemEffectsService(db_session)
    success, message, applied_effects = await service.use_item(test_user.id, inventory.id)

    assert success is False
    assert applied_effects is None
    assert "remaining" in message.lower()
