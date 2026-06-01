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
