from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock

import pytest
from sqlalchemy.dialects import postgresql

from app.services.learner_state import cleanup_observation_events

NOW = datetime(2026, 7, 13, tzinfo=UTC)


@pytest.mark.asyncio
async def test_cleanup_dry_run_counts_without_mutating_rows():
    session = MagicMock()
    session.scalar = AsyncMock(side_effect=[7, 3, None])
    session.execute = AsyncMock()

    result = await cleanup_observation_events(session, now=NOW, dry_run=True)

    assert result.payloads_eligible == 7
    assert result.audit_rows_eligible == 3
    session.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_cleanup_mutations_are_scoped_to_applied_rows_only():
    session = MagicMock()
    session.scalar = AsyncMock(side_effect=[7, 3, None])
    session.scalars = AsyncMock(return_value=MagicMock(all=MagicMock(return_value=[])))
    session.execute = AsyncMock(
        side_effect=[MagicMock(rowcount=5), MagicMock(rowcount=2)]
    )

    result = await cleanup_observation_events(session, now=NOW, dry_run=False)

    statements = [
        str(call.args[0].compile(dialect=postgresql.dialect())).lower()
        for call in session.execute.await_args_list
    ]
    delete_selector = str(
        session.scalars.await_args.args[0].compile(dialect=postgresql.dialect())
    ).lower()
    assert "status =" in statements[0] and "applied" in statements[0]
    assert "status =" in delete_selector and "applied" in delete_selector
    assert "id in" in statements[1]
    assert all(
        "pending" not in sql and "dead" not in sql
        for sql in [*statements, delete_selector]
    )
    assert result.payloads_cleared == 5
    assert result.audit_rows_deleted == 2
