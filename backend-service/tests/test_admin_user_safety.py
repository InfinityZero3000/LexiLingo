"""Sensitive admin actions always leave an audit row (gem caps: test_gem_limits.py)."""
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.routes import user_management as um


class _Result:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


class _Db:
    def __init__(self, user):
        self.user = user
        self.added = []
        self.order = []

    async def execute(self, _stmt):
        return _Result(self.user)

    def add(self, obj):
        self.added.append(obj)

    async def commit(self):
        self.order.append("commit")


def _request():
    return SimpleNamespace(state=SimpleNamespace(), client=None, headers={})


def _admin(level):
    return SimpleNamespace(id=uuid4(), username="boss", role_level=level)


def _target(level=0):
    return SimpleNamespace(
        id=uuid4(), email="a@b.c", username="learner", role_level=level, role_slug="user"
    )


def _audits(db):
    return [o for o in db.added if o.__class__.__name__ == "AuditLog"]


@pytest.mark.asyncio
async def test_permanent_delete_is_audited_before_the_account_disappears():
    victim = _target()
    db = _Db(victim)
    admin = _admin(2)

    async def fake_delete(session, user):
        # By now the audit row must already be queued with who the account was.
        assert len(_audits(session)) == 1
        assert victim.email in _audits(session)[0].details
        session.order.append("delete")

    with patch.object(um, "permanently_delete_user", new=fake_delete):
        await um.permanently_delete_user_account(victim.id, _request(), admin, db)

    assert db.order == ["delete", "commit"]
    assert _audits(db)[0].action == "permanent_delete"
    assert _audits(db)[0].user_id == admin.id


def test_bulk_action_is_capped_at_100_users():
    um.BulkActionRequest(user_ids=[str(uuid4()) for _ in range(100)], action="deactivate")
    with pytest.raises(ValidationError):
        um.BulkActionRequest(user_ids=[str(uuid4()) for _ in range(101)], action="deactivate")
