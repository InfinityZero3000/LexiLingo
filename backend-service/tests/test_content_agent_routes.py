import uuid
from types import SimpleNamespace

from fastapi.routing import APIRoute

from app.core.dependencies import get_current_admin
from app.routes import content_agent as content_agent_routes

router = content_agent_routes.router


def _dependency_calls(route: APIRoute) -> set:
    calls = set()
    pending = list(route.dependant.dependencies)
    while pending:
        dependency = pending.pop()
        if dependency.call is not None:
            calls.add(dependency.call)
        pending.extend(dependency.dependencies)
    return calls


def test_every_content_agent_route_requires_admin():
    routes = [route for route in router.routes if isinstance(route, APIRoute)]

    assert routes
    for route in routes:
        assert get_current_admin in _dependency_calls(route), route.path


async def test_cancel_locks_job_commits_and_revokes_worker(monkeypatch):
    job = SimpleNamespace(
        id=uuid.uuid4(),
        status="generating",
        celery_task_id="celery-task-1",
    )
    admin = SimpleNamespace(id=uuid.uuid4(), role_level=2)
    calls = {"locked": False, "commits": 0, "revoked": None}

    class FakeSession:
        async def commit(self):
            calls["commits"] += 1

    async def fake_get_job(_db, job_id, *, lock=False):
        assert job_id == job.id
        calls["locked"] = lock
        return job

    async def fake_cancel(_db, target):
        target.status = "cancelled"
        return target

    def fake_revoke(task_id, *, terminate):
        calls["revoked"] = (task_id, terminate)

    monkeypatch.setattr(content_agent_routes, "_get_job_or_404", fake_get_job)
    monkeypatch.setattr(
        content_agent_routes.ContentAgentJobService,
        "cancel",
        fake_cancel,
    )
    monkeypatch.setattr(content_agent_routes, "_audit", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        content_agent_routes,
        "_job_response",
        lambda target: {"id": str(target.id), "status": target.status},
    )
    monkeypatch.setattr(
        content_agent_routes.celery_app,
        "control",
        SimpleNamespace(revoke=fake_revoke),
        raising=False,
    )

    response = await content_agent_routes.cancel_job(
        job.id,
        db=FakeSession(),
        admin=admin,
    )

    assert response.data["status"] == "cancelled"
    assert calls == {
        "locked": True,
        "commits": 1,
        "revoked": ("celery-task-1", False),
    }


async def test_source_catalog_route_returns_validated_active_snapshots(monkeypatch):
    monkeypatch.setattr(content_agent_routes, "_require_enabled", lambda: None)
    monkeypatch.setattr(content_agent_routes, "ContentAgentClient", lambda: object())

    async def fake_catalog(_client):
        return [
            {
                "source_id": "oewn",
                "source_name": "oewn",
                "source_version": "2025",
                "snapshot_id": "oewn:2025:" + ("a" * 64),
                "official_url": "https://en-word.net/static/english-wordnet-2025.xml.gz",
                "license_id": "CC-BY-4.0",
                "license_url": "https://creativecommons.org/licenses/by/4.0/",
                "attribution_text": "Open English WordNet 2025",
                "retrieved_at": "2026-06-15T00:00:00Z",
                "raw_checksum": "a" * 64,
                "normalized_sha256": "b" * 64,
                "normalized_bytes": 100,
                "record_checksum_root": "c" * 64,
                "adapter_version": 1,
                "record_count": 100,
                "status": "active",
                "enabled": True,
            }
        ]

    monkeypatch.setattr(content_agent_routes, "get_source_catalog", fake_catalog)

    response = await content_agent_routes.list_sources(
        _=SimpleNamespace(id=uuid.uuid4())
    )

    assert response.data[0].source_id == "oewn"
    assert response.data[0].status == "active"
