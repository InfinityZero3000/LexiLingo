from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from app.services.fsrs_scheduler_service import FSRSSchedulerService


@pytest.mark.asyncio
async def test_count_due_vocabulary_returns_scalar_count():
    db = MagicMock()
    result = MagicMock()
    result.scalar.return_value = 4
    db.execute = AsyncMock(return_value=result)

    count = await FSRSSchedulerService().count_due_vocabulary(
        db,
        user_id=uuid4(),
        now=datetime(2026, 6, 1, tzinfo=timezone.utc),
    )

    assert count == 4
    db.execute.assert_awaited_once()


@pytest.mark.asyncio
async def test_due_words_returns_the_words():
    db = MagicMock()
    result = MagicMock()
    result.scalars.return_value.all.return_value = ["resilient", None, "approve"]
    db.execute = AsyncMock(return_value=result)

    words = await FSRSSchedulerService().due_words(db, user_id=uuid4())

    assert words == ["resilient", "approve"]
