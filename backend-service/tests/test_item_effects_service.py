from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.services.item_effects_service import DailyChallengeService, ItemEffectsService


def _result(value=None):
    result = MagicMock()
    result.scalar_one_or_none.return_value = value
    return result


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
async def test_hint_pack_handles_null_bonus_hints():
    service = ItemEffectsService(AsyncMock())
    attempt = SimpleNamespace(bonus_hints=None, hints_used=None)
    service._get_active_lesson_attempt = AsyncMock(return_value=attempt)

    success, _, effects = await service._handle_hint_pack(
        uuid4(),
        SimpleNamespace(),
        SimpleNamespace(effects={"quantity": 2}),
    )

    assert success is True
    assert attempt.bonus_hints == 2
    assert effects["hints_remaining"] == 5


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


@pytest.mark.asyncio
async def test_generic_use_rejects_cosmetic_without_consuming_inventory():
    inventory = SimpleNamespace(
        id=uuid4(),
        user_id=uuid4(),
        shop_item_id=uuid4(),
        quantity=1,
    )
    shop_item = SimpleNamespace(
        id=inventory.shop_item_id,
        item_type="avatar",
        name="Sunny Avatar",
        effects={"avatar_url": "https://example.com/avatar.svg"},
    )
    db = MagicMock()
    db.execute = AsyncMock(side_effect=[_result(inventory), _result(shop_item)])
    db.commit = AsyncMock()

    service = ItemEffectsService(db)
    success, message, effects = await service.use_item(
        inventory.user_id,
        inventory.id,
    )

    assert success is False
    assert "dedicated inventory endpoint" in message
    assert effects is None
    assert inventory.quantity == 1
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_daily_challenge_service_rejects_duplicate_claim():
    db = MagicMock()
    db.execute = AsyncMock(return_value=_result(SimpleNamespace()))
    db.add = MagicMock()
    db.commit = AsyncMock()

    service = DailyChallengeService(db)
    success, message, payload = await service.claim_challenge_reward(
        user_id=uuid4(),
        challenge_id="complete_lessons",
        xp_reward=20,
    )

    assert success is False
    assert "already claimed" in message.lower()
    assert payload["already_claimed"] is True
    db.add.assert_not_called()
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_daily_challenge_service_records_claim_and_commits_once():
    user_id = uuid4()
    user = SimpleNamespace(id=user_id, total_xp=5)
    db = MagicMock()
    db.execute = AsyncMock(
        side_effect=[
            _result(None),
            _result(user),
            _result(None),
        ]
    )
    db.add = MagicMock()
    db.commit = AsyncMock()
    db.rollback = AsyncMock()

    service = DailyChallengeService(db)
    with patch(
        "app.crud.gamification.LeaderboardCRUD.add_xp",
        new=AsyncMock(),
    ) as add_xp, patch(
        "app.crud.gamification.WalletCRUD.add_gems",
        new=AsyncMock(),
    ) as add_gems:
        success, message, payload = await service.claim_challenge_reward(
            user_id=user_id,
            challenge_id="complete_lessons",
            xp_reward=20,
            gems_reward=3,
        )

    added_model_names = [call.args[0].__class__.__name__ for call in db.add.call_args_list]

    assert success is True
    assert "Claimed" in message
    assert payload["xp_earned"] == 20
    assert payload["gems_earned"] == 3
    assert user.total_xp == 25
    assert "DailyActivity" in added_model_names
    assert "ChallengeRewardClaim" in added_model_names
    add_xp.assert_awaited_once_with(db, user_id, 20)
    add_gems.assert_awaited_once()
    assert add_gems.await_args.kwargs["commit"] is False
    db.commit.assert_awaited_once()
