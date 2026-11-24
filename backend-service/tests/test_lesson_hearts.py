"""Hearts are enforced by the server: no answers at 0, refill or restart brings them back."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, patch

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Lesson
from app.models.gamification import ShopItem, UserInventory
from app.models.progress import LessonAttempt
from app.models.user import User

WRONG = (False, "right", None, None)


def _answer_body() -> dict:
    return {
        "question_id": "22222222-2222-2222-2222-222222222222",
        "question_type": "fill_blank",
        "user_answer": "nope",
        "time_spent_ms": 3000,
        "hint_used": False,
    }


def _grade_wrong():
    return patch("app.routes.learning._validate_answer", AsyncMock(return_value=WRONG))


@pytest.mark.asyncio
class TestLessonHearts:
    async def test_answer_that_takes_last_heart_is_accepted(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_lesson_attempt: LessonAttempt,
    ):
        test_lesson_attempt.lives_remaining = 1
        await db_session.commit()

        with _grade_wrong():
            response = await async_client.post(
                f"/api/v1/learning/attempts/{test_lesson_attempt.id}/answer",
                json=_answer_body(),
                headers=auth_headers,
            )

        assert response.status_code == 200
        data = response.json()["data"]
        assert data["is_correct"] is False
        assert data["lives_remaining"] == 0

    async def test_answer_at_zero_hearts_is_refused(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_lesson_attempt: LessonAttempt,
    ):
        test_lesson_attempt.lives_remaining = 0
        await db_session.commit()

        response = await async_client.post(
            f"/api/v1/learning/attempts/{test_lesson_attempt.id}/answer",
            json=_answer_body(),
            headers=auth_headers,
        )

        assert response.status_code == 409
        assert response.json()["error"]["message"] == "out_of_hearts"
        await db_session.refresh(test_lesson_attempt)
        assert test_lesson_attempt.correct_answers == 0
        assert test_lesson_attempt.xp_earned == 0

    async def test_heart_refill_lets_an_empty_attempt_answer_again(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_user: User,
        test_lesson_attempt: LessonAttempt,
    ):
        test_lesson_attempt.lives_remaining = 0
        item = ShopItem(
            name="Heart Refill",
            description="x",
            item_type="heart_refill",
            price_gems=15,
            is_available=True,
            effects={"hearts": 3},
        )
        db_session.add(item)
        await db_session.flush()
        inventory = UserInventory(
            user_id=test_user.id, shop_item_id=item.id, quantity=1
        )
        db_session.add(inventory)
        await db_session.commit()

        used = await async_client.post(
            "/api/v1/gamification/inventory/use",
            json={"inventory_id": str(inventory.id)},
            headers=auth_headers,
        )
        assert used.status_code == 200, used.text

        with _grade_wrong():
            response = await async_client.post(
                f"/api/v1/learning/attempts/{test_lesson_attempt.id}/answer",
                json=_answer_body(),
                headers=auth_headers,
            )
        assert response.status_code == 200
        assert response.json()["data"]["lives_remaining"] == 2

    async def test_starting_again_at_zero_hearts_gives_a_fresh_attempt(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_lesson: Lesson,
        test_lesson_attempt: LessonAttempt,
    ):
        test_lesson_attempt.lives_remaining = 0
        await db_session.commit()

        response = await async_client.post(
            f"/api/v1/learning/lessons/{test_lesson.id}/start",
            headers=auth_headers,
        )

        assert response.status_code == 200
        data = response.json()["data"]
        assert data["attempt_id"] != str(test_lesson_attempt.id)
        assert data["lives_remaining"] == 3
        await db_session.refresh(test_lesson_attempt)
        assert test_lesson_attempt.finished_at is not None
        assert test_lesson_attempt.passed is False

    async def test_complete_after_running_out_is_still_idempotent(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_lesson_attempt: LessonAttempt,
    ):
        test_lesson_attempt.lives_remaining = 0
        test_lesson_attempt.score = 0
        await db_session.commit()
        url = f"/api/v1/learning/attempts/{test_lesson_attempt.id}/complete"

        first = await async_client.post(url, headers=auth_headers)
        second = await async_client.post(url, headers=auth_headers)

        assert first.status_code == second.status_code == 200
        assert first.json()["data"] == second.json()["data"]


@pytest.mark.asyncio
class TestAnswerReplay:
    async def test_resending_a_correct_answer_credits_nothing_more(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_lesson_attempt: LessonAttempt,
    ):
        url = f"/api/v1/learning/attempts/{test_lesson_attempt.id}/answer"
        right = (True, "right", None, None)
        with patch("app.routes.learning._validate_answer", AsyncMock(return_value=right)):
            first = await async_client.post(url, json=_answer_body(), headers=auth_headers)
            second = await async_client.post(url, json=_answer_body(), headers=auth_headers)

        assert first.status_code == second.status_code == 200
        assert first.json()["data"]["xp_earned"] > 0
        replay = second.json()["data"]
        assert replay["is_correct"] is True
        assert replay["xp_earned"] == 0
        assert replay["question_attempt_id"] == first.json()["data"]["question_attempt_id"]

        await db_session.refresh(test_lesson_attempt)
        assert test_lesson_attempt.correct_answers == 1
        assert test_lesson_attempt.xp_earned == first.json()["data"]["xp_earned"]

    async def test_a_wrong_answer_can_still_be_retried(
        self,
        async_client: AsyncClient,
        db_session: AsyncSession,
        auth_headers: dict,
        test_lesson_attempt: LessonAttempt,
    ):
        url = f"/api/v1/learning/attempts/{test_lesson_attempt.id}/answer"
        with _grade_wrong():
            await async_client.post(url, json=_answer_body(), headers=auth_headers)
        right = (True, "right", None, None)
        with patch("app.routes.learning._validate_answer", AsyncMock(return_value=right)):
            retry = await async_client.post(url, json=_answer_body(), headers=auth_headers)

        assert retry.json()["data"]["xp_earned"] > 0
        await db_session.refresh(test_lesson_attempt)
        assert test_lesson_attempt.correct_answers == 1
