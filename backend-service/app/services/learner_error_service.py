"""Best-effort persistence for learner errors."""

import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.learner_error import LearnerError

logger = logging.getLogger(__name__)


async def record_learner_error(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    source: str,
    is_correct: bool,
    skill: str | None = None,
    error_type: str | None = None,
    submitted_answer: str | None = None,
    correct_answer: str | None = None,
    context: dict | None = None,
) -> None:
    if is_correct:
        return

    try:
        async with db.begin_nested():
            db.add(
                LearnerError(
                    user_id=user_id,
                    source=source,
                    skill=skill,
                    error_type=error_type,
                    submitted_answer=submitted_answer,
                    correct_answer=correct_answer,
                    context=context,
                )
            )
            await db.flush()
    except Exception:
        logger.exception(
            "Failed to record learner error for user %s from %s",
            user_id,
            source,
        )
