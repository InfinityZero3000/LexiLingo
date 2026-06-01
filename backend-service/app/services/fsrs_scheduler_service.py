"""FSRS scheduler read adapter.

This module does not calculate FSRS. It reads the schedule already produced by
vocabulary reviews and gives background jobs a small, testable contract.
"""

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.vocabulary import UserVocabulary, VocabularyStatus


class FSRSSchedulerService:
    """Read-only helper for due vocabulary checks."""

    async def count_due_vocabulary(
        self,
        db: AsyncSession,
        *,
        user_id: UUID,
        now: datetime | None = None,
    ) -> int:
        """Count non-archived vocabulary due for review at `now`."""
        now = now or datetime.now(timezone.utc)
        result = await db.execute(
            select(func.count())
            .select_from(UserVocabulary)
            .where(
                and_(
                    UserVocabulary.user_id == user_id,
                    UserVocabulary.next_review_date <= now,
                    UserVocabulary.status != VocabularyStatus.ARCHIVED,
                )
            )
        )
        return int(result.scalar() or 0)
