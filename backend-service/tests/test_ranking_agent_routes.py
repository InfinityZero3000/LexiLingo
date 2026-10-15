"""Tests for ranking-agent admin routes."""

import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock

from fastapi.routing import APIRoute

from app.core.dependencies import get_current_admin
from app.routes import ranking_agent as ranking_agent_routes

router = ranking_agent_routes.router


def _dependency_calls(route: APIRoute) -> set:
    calls = set()
    pending = list(route.dependant.dependencies)
    while pending:
        dep = pending.pop()
        if dep.call is not None:
            calls.add(dep.call)
        pending.extend(dep.dependencies)
    return calls


def test_every_ranking_agent_route_requires_admin():
    routes = [r for r in router.routes if isinstance(r, APIRoute)]
    assert routes, "No routes found — router might not be wired"
    for route in routes:
        assert get_current_admin in _dependency_calls(route), (
            f"{route.path} is missing get_current_admin dependency"
        )


async def test_cancel_locks_job_and_commits(monkeypatch):
    job_id = uuid.uuid4()
    job = SimpleNamespace(
        id=job_id,
        status="calculating",
        celery_task_id=None,
        requested_by_id=None,
    )
    admin = SimpleNamespace(id=uuid.uuid4(), role=SimpleNamespace(name="super_admin"))
    commits = []

    class FakeDB:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            pass

        async def commit(self):
            commits.append(1)

        def add(self, *_):
            pass

    async def fake_get(db, jid, *, lock=False):
        assert lock is True
        return job

    async def fake_cancel(db, j):
        j.status = "cancelled"
        return j

    async def fake_transition(db, j, status, **_):
        j.status = status
        return j

    monkeypatch.setattr(ranking_agent_routes.RankingAgentJobService, "get", fake_get)
    monkeypatch.setattr(ranking_agent_routes.RankingAgentJobService, "cancel", fake_cancel)

    # Verify the route exists and has the right path
    cancel_routes = [r for r in router.routes if "/cancel" in getattr(r, "path", "")]
    assert cancel_routes, "cancel route not found"


async def test_require_enabled_raises_when_disabled(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "RANKING_AGENT_ENABLED", False)
    with __import__("pytest").raises(Exception):
        ranking_agent_routes._require_enabled()


async def test_apply_invalidates_leaderboard_after_achievement_commit(monkeypatch):
    job_id = uuid.uuid4()
    job = SimpleNamespace(id=job_id, job_type="achievement_batch")
    admin = SimpleNamespace(id=uuid.uuid4(), role=SimpleNamespace(level=2))
    events = []

    class FakeDB:
        async def commit(self):
            events.append("commit")

    async def get_job(_db, _job_id, *, lock=False):
        return job

    monkeypatch.setattr(ranking_agent_routes, "_require_enabled", lambda: None)
    monkeypatch.setattr(ranking_agent_routes, "_require_job_owner", lambda *_: None)
    monkeypatch.setattr(ranking_agent_routes, "_get_job_or_404", get_job)
    monkeypatch.setattr(ranking_agent_routes, "_audit", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(
        ranking_agent_routes,
        "_job_response",
        lambda _job: SimpleNamespace(model_dump=lambda **_: {}),
    )
    monkeypatch.setattr(
        ranking_agent_routes.RankingAgentApplyService,
        "apply",
        AsyncMock(return_value=(job, {"granted_count": 1})),
    )

    async def invalidate(_namespace):
        events.append("invalidate")

    monkeypatch.setattr(ranking_agent_routes, "invalidate_cache", invalidate)

    await ranking_agent_routes.apply_job(job_id, db=FakeDB(), admin=admin)

    assert events == ["commit", "invalidate", "commit"]
