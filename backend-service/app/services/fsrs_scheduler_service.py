"""FSRS scheduler read adapter.

This module does not calculate FSRS. It reads the schedule already produced by
vocabulary reviews and gives background jobs a small, testable contract.
"""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.vocabulary import _valid_definition_conditions
from app.models.vocabulary import UserVocabulary, VocabularyItem, VocabularyStatus


def _due_conditions(user_id: UUID, now: datetime) -> tuple:
    # The same filter as the review session: a reminder that counted words with
    # a placeholder definition promised more than the session would show.
    return (
        and_(
            UserVocabulary.user_id == user_id,
            UserVocabulary.next_review_date <= now,
            UserVocabulary.status != VocabularyStatus.ARCHIVED,
        ),
        *_valid_definition_conditions(),
    )


class FSRSSchedulerService:
    """Read-only helper for due vocabulary checks."""

    async def count_due_vocabulary(
        self,
        db: AsyncSession,
        *,
        user_id: UUID,
        now: datetime | None = None,
    ) -> int:
        """Count reviewable vocabulary due at `now`."""
        now = now or datetime.now(UTC)
        result = await db.execute(
            select(func.count())
            .select_from(UserVocabulary)
            .join(VocabularyItem, VocabularyItem.id == UserVocabulary.vocabulary_id)
            .where(*_due_conditions(user_id, now))
        )
        return int(result.scalar() or 0)

    async def due_words(
        self,
        db: AsyncSession,
        *,
        user_id: UUID,
        now: datetime | None = None,
        limit: int = 3,
    ) -> list[str]:
        """The most overdue words, for a reminder to name."""
        now = now or datetime.now(UTC)
        result = await db.execute(
            select(VocabularyItem.word)
            .select_from(UserVocabulary)
            .join(VocabularyItem, VocabularyItem.id == UserVocabulary.vocabulary_id)
            .where(*_due_conditions(user_id, now))
            .order_by(UserVocabulary.next_review_date)
            .limit(limit)
        )
        return [word for word in result.scalars().all() if word]
