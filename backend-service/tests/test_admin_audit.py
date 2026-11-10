"""Every successful admin write leaves exactly one audit row; reads and failures leave none."""
import json
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import FastAPI, HTTPException, Request
from httpx import ASGITransport, AsyncClient

from app.core.admin_audit_middleware import AdminAuditMiddleware
from app.core.database import get_db
from app.services.admin_audit import record_admin_action

ACTOR = uuid4()


class _Session:
    def __init__(self, sink):
        self.sink = sink

    def add(self, entry):
        self.sink.append(entry)

    async def commit(self):
        return None


def _app(sink):
    app = FastAPI()
    app.add_middleware(AdminAuditMiddleware)

    async def fake_db():
        yield _Session(sink)

    app.dependency_overrides[get_db] = fake_db

    def as_admin(request: Request):
        request.state.admin_actor_id = ACTOR

    @app.post("/api/v1/admin/courses")
    async def create_course(request: Request):
        as_admin(request)
        return {"ok": True}

    @app.put("/api/v1/admin/courses/{course_id}")
    async def update_course(course_id: str, request: Request):
        as_admin(request)
        return {"ok": True}

    @app.get("/api/v1/admin/courses")
    async def list_courses(request: Request):
        as_admin(request)
        return []

    @app.post("/api/v1/admin/shop")
    async def rejected(request: Request):
        as_admin(request)
        raise HTTPException(status_code=422, detail="bad")

    @app.post("/api/v1/learner/answer")
    async def not_an_admin_call():
        return {"ok": True}

    @app.post("/api/v1/admin/users/{user_id}/gift")
    async def explicit(user_id: str, request: Request):
        as_admin(request)
        record_admin_action(
            _Session(sink), SimpleNamespace(id=ACTOR), "gift", "user", user_id,
            {"gems": 10}, request,
        )
        return {"ok": True}

    return app


async def _call(app, method, url):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as client:
        return await client.request(method, url)


@pytest.mark.asyncio
async def test_admin_write_is_recorded_with_actor_and_resource():
    sink = []
    await _call(_app(sink), "PUT", "/api/v1/admin/courses/abc")

    (row,) = sink
    assert row.user_id == ACTOR
    assert (row.action, row.resource_type, row.resource_id) == ("update", "courses", "abc")
    assert "PUT /api/v1/admin/courses/{course_id}" in row.details


@pytest.mark.asyncio
async def test_create_maps_to_create():
    sink = []
    await _call(_app(sink), "POST", "/api/v1/admin/courses")
    assert [r.action for r in sink] == ["create"]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "method,url",
    [
        ("GET", "/api/v1/admin/courses"),       # reads are not audited
        ("POST", "/api/v1/admin/shop"),         # failed write
        ("POST", "/api/v1/learner/answer"),     # not an admin call
    ],
)
async def test_reads_failures_and_non_admin_calls_are_not_recorded(method, url):
    sink = []
    await _call(_app(sink), method, url)
    assert sink == []


@pytest.mark.asyncio
async def test_explicit_audit_suppresses_the_generic_row():
    sink = []
    await _call(_app(sink), "POST", "/api/v1/admin/users/u1/gift")

    (row,) = sink
    assert row.action == "gift"
    assert json.loads(row.details) == {"gems": 10}
