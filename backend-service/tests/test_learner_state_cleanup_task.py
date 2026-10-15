from unittest.mock import AsyncMock, MagicMock

import pytest

from app.core.celery_app import celery_app
from app.services.learner_state import ObservationCleanupResult
from app.tasks import learner_state as task_module


class _SessionContext:
    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        return self.session

    async def __aexit__(self, *_args):
        return None


def test_learner_observation_cleanup_is_scheduled() -> None:
    schedule = celery_app.conf.beat_schedule["cleanup-learner-observations"]

    assert schedule["task"] == "app.tasks.learner_state.cleanup_learner_observations"
    include = getattr(celery_app.conf, "include", ())
    assert not include or "app.tasks.learner_state" in include


@pytest.mark.asyncio
async def test_learner_observation_cleanup_applies_and_commits(monkeypatch) -> None:
    session = MagicMock(commit=AsyncMock())
    cleanup = AsyncMock(
        return_value=ObservationCleanupResult(
            payloads_eligible=7,
            audit_rows_eligible=3,
            payloads_cleared=5,
            audit_rows_deleted=2,
            cleanup_lag_seconds=1.0,
        )
    )
    monkeypatch.setattr(task_module, "AsyncSessionLocal", lambda: _SessionContext(session))
    monkeypatch.setattr(task_module, "cleanup_observation_events", cleanup)
    close_db = AsyncMock()
    monkeypatch.setattr(task_module, "close_db", close_db)

    result = await task_module._cleanup_learner_observations()

    assert result == {
        "dry_run": False,
        "payloads_eligible": 7,
        "audit_rows_eligible": 3,
        "payloads_cleared": 5,
        "audit_rows_deleted": 2,
        "cleanup_lag_seconds": 1.0,
    }
    cleanup.assert_awaited_once()
    assert cleanup.await_args.args == (session,)
    assert cleanup.await_args.kwargs["now"].tzinfo is not None
    assert cleanup.await_args.kwargs["dry_run"] is False
    session.commit.assert_awaited_once_with()
    close_db.assert_awaited_once_with()
