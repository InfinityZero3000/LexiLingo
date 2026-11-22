"""Server-verified Lucky Clover: roll on use, XP rescue on completion."""

import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.routes.games import complete_game_session
from app.schemas.games import GameSessionCompleteRequest
from app.services.item_effects_service import ItemEffectsService


def _service(user_id, session, roll):
    inventory = MagicMock(quantity=1)
    shop_item = MagicMock(
        item_type="lucky_clover", name="Lucky Clover", effects={"chance": 0.3}
    )
    shop_item.name = "Lucky Clover"
    results = [MagicMock(), MagicMock()]
    results[0].scalar_one_or_none.return_value = inventory
    results[1].scalar_one_or_none.return_value = shop_item
    db = MagicMock()
    db.execute = AsyncMock(side_effect=results)
    db.commit = AsyncMock()
    return ItemEffectsService(db), inventory, db


def _patched(session, roll):
    rng = MagicMock()
    rng.random.return_value = roll
    return (
        patch(
            "app.crud.games.get_game_session_for_update",
            new_callable=AsyncMock,
            return_value=session,
        ),
        patch("app.services.item_effects_service.secrets.SystemRandom", return_value=rng),
    )


def _session(user_id, **over):
    s = MagicMock()
    s.user_id = user_id
    s.completed_at = None
    s.session_data = {"expected_items": []}
    for k, v in over.items():
        setattr(s, k, v)
    return s


class TestUseCloverWithSession:
    @pytest.mark.asyncio
    @pytest.mark.parametrize("roll,rescue", [(0.1, True), (0.9, False)])
    async def test_roll_is_stored_and_item_consumed(self, roll, rescue):
        user_id = uuid.uuid4()
        session = _session(user_id)
        service, inventory, db = _service(user_id, session, roll)
        p1, p2 = _patched(session, roll)
        with p1, p2:
            ok, _, effects = await service.use_item(
                user_id, uuid.uuid4(), game_session_id=uuid.uuid4()
            )
        assert ok is True
        assert effects["rescue"] is rescue
        assert effects["chance"] == 0.3
        assert session.session_data["lucky_clovers"] == [rescue]
        assert inventory.quantity == 0
        db.commit.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_refused_for_completed_session_without_consuming(self):
        user_id = uuid.uuid4()
        session = _session(user_id, completed_at=datetime.now(timezone.utc))
        service, inventory, db = _service(user_id, session, 0.1)
        p1, p2 = _patched(session, 0.1)
        with p1, p2:
            ok, message, effects = await service.use_item(
                user_id, uuid.uuid4(), game_session_id=uuid.uuid4()
            )
        assert ok is False and effects is None
        assert "completed" in message
        assert inventory.quantity == 1
        db.commit.assert_not_awaited()
        assert "lucky_clovers" not in session.session_data

    @pytest.mark.asyncio
    async def test_refused_for_another_users_session(self):
        user_id = uuid.uuid4()
        session = _session(uuid.uuid4())
        service, inventory, db = _service(user_id, session, 0.1)
        p1, p2 = _patched(session, 0.1)
        with p1, p2:
            ok, _, _ = await service.use_item(
                user_id, uuid.uuid4(), game_session_id=uuid.uuid4()
            )
        assert ok is False
        assert inventory.quantity == 1

    @pytest.mark.asyncio
    async def test_without_session_keeps_legacy_behaviour(self):
        user_id = uuid.uuid4()
        service, inventory, db = _service(user_id, None, 0.1)
        ok, _, effects = await service.use_item(user_id, uuid.uuid4())
        assert ok is True
        assert "rescue" not in effects
        assert inventory.quantity == 0


def _complete_session(user_id, rolls):
    s = MagicMock()
    s.id = uuid.uuid4()
    s.user_id = user_id
    s.game_type = "grammar_quiz"
    s.started_at = datetime.now(timezone.utc) - timedelta(seconds=20)
    s.created_at = s.started_at
    s.completed_at = None
    s.xp_awarded = False
    s.session_data = {
        "lucky_clovers": rolls,
        "expected_items": [
            {"id": "1", "answer": "is", "xp_value": 10},
            {"id": "2", "answer": "are", "xp_value": 7},
            {"id": "3", "answer": "am", "xp_value": 5},
        ],
    }
    return s


async def _complete(session, user_id, rescued_ids):
    user = MagicMock()
    user.id = user_id
    db = MagicMock()
    db.commit = AsyncMock()
    xp_result = MagicMock(xp_awarded=0)
    xp_result.to_dict.return_value = {}
    with patch(
        "app.routes.games.get_game_session_for_update",
        new_callable=AsyncMock, return_value=session,
    ), patch(
        "app.routes.games.award_xp_transaction",
        new_callable=AsyncMock, return_value=xp_result,
    ) as award, patch(
        "app.routes.games.record_learner_error", new_callable=AsyncMock
    ) as lapse, patch(
        "app.routes.games.record_game_grammar_lapse", new_callable=AsyncMock
    ), patch(
        "app.routes.games.ItemEffectsService.get_xp_multiplier",
        new_callable=AsyncMock, return_value=1.0,
    ), patch(
        "app.routes.games.update_user_streak", new_callable=AsyncMock
    ), patch(
        "app.routes.games.record_exercise_results_for_user", new_callable=AsyncMock
    ), patch(
        "app.routes.games.check_achievements_for_user",
        new_callable=AsyncMock, return_value=[],
    ), patch("app.routes.games.invalidate_cache", new_callable=AsyncMock):
        response = await complete_game_session(
            session_id=session.id,
            body=GameSessionCompleteRequest(
                answers=[
                    {"id": "1", "answer": "is"},
                    {"id": "2", "answer": "wrong"},
                    {"id": "3", "answer": "wrong"},
                ],
                rescued_ids=rescued_ids,
            ),
            db=db,
            current_user=user,
        )
    return response, award, lapse


class TestCompletionWithRescue:
    @pytest.mark.asyncio
    async def test_rescued_xp_added_and_evidence_kept(self):
        uid = uuid.uuid4()
        s = _complete_session(uid, [True])
        response, award, lapse = await _complete(s, uid, ["2"])
        assert response.correct_count == 1
        assert response.raw_xp == 10
        assert response.base_xp == 17
        assert response.rescued_count == 1
        assert award.await_args.kwargs["base_xp"] == 17
        assert lapse.await_count == 2
        assert s.correct_answers == 1
        assert s.session_data["score_result"]["rescued_ids"] == ["2"]
        assert s.session_data["score_result"]["rescued_xp"] == 7

    @pytest.mark.asyncio
    async def test_capped_at_successful_rolls(self):
        uid = uuid.uuid4()
        s = _complete_session(uid, [False, True, False])
        response, _, _ = await _complete(s, uid, ["3", "2"])
        assert response.rescued_count == 1
        assert response.base_xp == 15

    @pytest.mark.asyncio
    async def test_invalid_and_duplicate_ids_ignored(self):
        uid = uuid.uuid4()
        s = _complete_session(uid, [True, True, True])
        response, _, _ = await _complete(s, uid, ["1", "nope", "2", "2"])
        assert response.rescued_count == 1
        assert response.base_xp == 17

    @pytest.mark.asyncio
    async def test_no_rolls_no_rescue(self):
        uid = uuid.uuid4()
        s = _complete_session(uid, [])
        response, _, _ = await _complete(s, uid, ["2"])
        assert response.rescued_count == 0
        assert response.base_xp == 10

    @pytest.mark.asyncio
    async def test_replay_returns_same_numbers(self):
        uid = uuid.uuid4()
        s = _complete_session(uid, [True])
        first, _, _ = await _complete(s, uid, ["2"])
        s.completed_at = datetime.now(timezone.utc)
        s.xp_awarded = True
        s.correct_answers = first.correct_count
        s.total_questions = first.total_count
        s.duration_seconds = first.duration_seconds
        award = MagicMock(xp_awarded=0, base_xp=17)
        award.to_dict.return_value = {}
        user = MagicMock(id=uid)
        with patch(
            "app.routes.games.get_game_session_for_update",
            new_callable=AsyncMock, return_value=s,
        ), patch(
            "app.routes.games.get_existing_xp_award",
            new_callable=AsyncMock, return_value=award,
        ):
            again = await complete_game_session(
                session_id=s.id,
                body=GameSessionCompleteRequest(rescued_ids=["3"]),
                db=MagicMock(), current_user=user,
            )
        assert again.base_xp == first.base_xp == 17
        assert again.rescued_count == 1
        assert again.award_status == "already_awarded"
