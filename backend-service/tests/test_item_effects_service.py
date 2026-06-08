from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.services.item_effects_service import ItemEffectsService


@pytest.mark.asyncio
async def test_hint_pack_adds_bonus_hints_to_active_attempt():
    service = ItemEffectsService(AsyncMock())
    attempt = SimpleNamespace(bonus_hints=1, hints_used=2)
    service._get_active_lesson_attempt = AsyncMock(return_value=attempt)
    item = SimpleNamespace(effects={"quantity": 5})

    success, _, effects = await service._handle_hint_pack(
        uuid4(),
        SimpleNamespace(),
        item,
    )

    assert success is True
    assert attempt.bonus_hints == 6
    assert effects["hints_remaining"] == 7


@pytest.mark.asyncio
async def test_hint_pack_requires_active_attempt():
    service = ItemEffectsService(AsyncMock())
    service._get_active_lesson_attempt = AsyncMock(return_value=None)

    success, message, effects = await service._handle_hint_pack(
        uuid4(),
        SimpleNamespace(),
        SimpleNamespace(effects={"quantity": 5}),
    )

    assert success is False
    assert "Start a lesson" in message
    assert effects is None


@pytest.mark.asyncio
async def test_heart_refill_restores_configured_maximum():
    service = ItemEffectsService(AsyncMock())
    attempt = SimpleNamespace(lives_remaining=0)
    service._get_active_lesson_attempt = AsyncMock(return_value=attempt)

    success, _, effects = await service._handle_heart_refill(
        uuid4(),
        SimpleNamespace(),
        SimpleNamespace(effects={"hearts": 3}),
    )

    assert success is True
    assert attempt.lives_remaining == 3
    assert effects["hearts_restored"] == 3
