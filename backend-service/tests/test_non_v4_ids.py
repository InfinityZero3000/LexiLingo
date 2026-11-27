"""Ids come from the database, and not all of them are v4 (the seeded roles are not)."""

import uuid
from pathlib import Path

from app.models.rbac import Role

SCHEMA_DIR = Path(__file__).resolve().parents[1] / "app" / "schemas"
SEEDED_ID = uuid.UUID("00000000-0000-0000-0000-000000000003")


async def test_role_list_accepts_the_migration_seeded_role_ids(
    async_client, db_session, admin_headers
):
    db_session.add(
        Role(id=SEEDED_ID, name="Seeded", slug="seeded", level=0, is_system=True, is_active=True)
    )
    await db_session.commit()

    response = await async_client.get("/api/v1/admin/rbac/roles", headers=admin_headers)

    assert response.status_code == 200, response.text
    assert str(SEEDED_ID) in {role["id"] for role in response.json()}


def test_no_schema_requires_a_version_4_id():
    offenders = [p.name for p in SCHEMA_DIR.rglob("*.py") if "UUID4" in p.read_text()]
    assert offenders == []
