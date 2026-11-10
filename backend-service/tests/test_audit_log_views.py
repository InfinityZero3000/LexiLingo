"""Audit log listing, filter facets and CSV export."""
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.routes import rbac


def _log(**over):
    base = dict(
        id=uuid4(), user_id=uuid4(), action="update", resource_type="courses",
        resource_id="c1", details="PUT /api/v1/admin/courses/{course_id}",
        ip_address="1.2.3.4", user_agent="pytest",
        created_at=datetime(2026, 11, 10, tzinfo=timezone.utc),
    )
    base.update(over)
    return SimpleNamespace(**base)


class _Result:
    def __init__(self, rows=(), scalar=0):
        self._rows, self._scalar = list(rows), scalar

    def all(self):
        return self._rows

    def scalar(self):
        return self._scalar

    def scalars(self):
        return self


class _Db:
    def __init__(self, *results):
        self._results = list(results)

    async def execute(self, _stmt):
        return self._results.pop(0)


@pytest.mark.asyncio
async def test_list_returns_the_actor_alongside_each_row():
    db = _Db(_Result(scalar=1), _Result([(_log(), "boss", "boss@x.io")]))

    data = await rbac.list_audit_logs(
        1, 50, None, None, None, None, None, None, None, SimpleNamespace(), db
    )

    assert data["total"] == 1
    assert data["logs"][0]["actor"] == {"username": "boss", "email": "boss@x.io"}
    assert data["logs"][0]["user_agent"] == "pytest"


@pytest.mark.asyncio
async def test_row_without_an_actor_is_still_listed():
    db = _Db(_Result(scalar=1), _Result([(_log(user_id=None), None, None)]))

    data = await rbac.list_audit_logs(
        1, 50, None, None, None, None, None, None, None, SimpleNamespace(), db
    )

    assert data["logs"][0]["actor"] is None


@pytest.mark.asyncio
async def test_facets_list_the_values_that_exist():
    db = _Db(_Result(["create", "update"]), _Result(["courses", "user"]))

    data = await rbac.audit_log_facets(SimpleNamespace(), db)

    assert data == {"actions": ["create", "update"], "resource_types": ["courses", "user"]}


@pytest.mark.asyncio
async def test_csv_export_neutralises_spreadsheet_formulas():
    nasty = _log(details="=HYPERLINK(\"http://evil\")", resource_id="+1")
    db = _Db(_Result([(nasty, "boss", "boss@x.io")]))

    response = await rbac.export_audit_logs(
        None, None, None, None, None, None, None, SimpleNamespace(), db
    )

    body = response.body.decode("utf-8-sig")
    assert response.media_type.startswith("text/csv")
    assert "'=HYPERLINK" in body
    assert "'+1" in body
    assert body.splitlines()[0].startswith("created_at,actor,actor_email,action")
