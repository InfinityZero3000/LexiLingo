import uuid
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.models.learner_error import LearnerError
from app.services.learner_error_service import record_learner_error


@pytest.mark.asyncio
async def test_correct_answer_does_not_write() -> None:
    db = MagicMock()
    db.flush = AsyncMock()

    await record_learner_error(
        db,
        user_id=uuid.uuid4(),
        source="exercise",
        is_correct=True,
    )

    db.begin_nested.assert_not_called()
    db.add.assert_not_called()
    db.flush.assert_not_awaited()


@pytest.mark.asyncio
async def test_incorrect_answer_is_recorded() -> None:
    db = MagicMock()
    db.flush = AsyncMock()
    user_id = uuid.uuid4()
    context = {"lesson_id": "lesson-1", "concept_id": "concept-1"}

    await record_learner_error(
        db,
        user_id=user_id,
        source="exercise",
        is_correct=False,
        skill="vocabulary",
        error_type="spelling",
        submitted_answer="helo",
        correct_answer="hello",
        context=context,
    )

    db.begin_nested.assert_called_once_with()
    db.add.assert_called_once()
    error = db.add.call_args.args[0]
    assert isinstance(error, LearnerError)
    assert error.user_id == user_id
    assert error.source == "exercise"
    assert error.skill == "vocabulary"
    assert error.error_type == "spelling"
    assert error.submitted_answer == "helo"
    assert error.correct_answer == "hello"
    assert error.context == context
    db.flush.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_database_failure_does_not_raise() -> None:
    db = MagicMock()
    db.flush = AsyncMock(side_effect=RuntimeError("database unavailable"))

    await record_learner_error(
        db,
        user_id=uuid.uuid4(),
        source="game",
        is_correct=False,
    )

    db.flush.assert_awaited_once_with()
