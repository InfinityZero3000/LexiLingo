"""A device re-registered by a different account must change owner."""
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

from sqlalchemy.dialects import postgresql

from app.routes.devices import register_device
from app.schemas.devices import DeviceRegisterRequest


class _Result:
    def __init__(self, row):
        self._row = row

    def scalar_one(self):
        return self._row


class _FakeDb:
    def __init__(self):
        self.statements = []
        now = datetime.now(timezone.utc)
        self.row = SimpleNamespace(
            id=uuid4(),
            device_id="dev-1",
            device_type="android",
            device_name=None,
            fcm_token=None,
            last_active=now,
            created_at=now,
        )

    def get_bind(self):
        return SimpleNamespace(dialect=SimpleNamespace(name="postgresql"))

    async def execute(self, stmt):
        self.statements.append(stmt)
        return _Result(self.row)

    async def commit(self):
        return None

    async def refresh(self, _row):
        return None


async def test_upsert_moves_device_to_the_registering_user():
    db = _FakeDb()
    user = SimpleNamespace(id=uuid4())
    request = DeviceRegisterRequest(device_id="dev-1", device_type="android")

    await register_device(request, db=db, current_user=user)

    sql = str(db.statements[0].compile(dialect=postgresql.dialect()))
    update_clause = sql.split("DO UPDATE SET", 1)[1]
    assert "user_id" in update_clause
    assert "device_type" in update_clause
