"""Idempotent permission seeding in plain Core, so a migration and a test can both run it."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

import sqlalchemy as sa

from app.core.db_types import GUID, TZDateTime

_permissions = sa.table(
    "permissions",
    sa.column("id", GUID()), sa.column("name"), sa.column("slug"), sa.column("resource"),
    sa.column("action"), sa.column("description"), sa.column("created_at", TZDateTime),
)
_roles = sa.table("roles", sa.column("id", GUID()), sa.column("slug"))
_role_permissions = sa.table(
    "role_permissions",
    sa.column("id", GUID()), sa.column("role_id", GUID()), sa.column("permission_id", GUID()),
    sa.column("granted_at", TZDateTime),
)

# Wildcards and user deletion are never part of an admin's default set.
ADMIN_WITHHELD = {"users:delete", "users:manage", "rbac:manage", "courses:manage"}


def seed_permissions(conn: sa.Connection, catalog: dict[str, list[str]]) -> None:
    now = datetime.now(timezone.utc)
    slugs: list[str] = []
    for resource, actions in catalog.items():
        for action in actions:
            slug = f"{resource}:{action}"
            slugs.append(slug)
            if conn.execute(sa.select(_permissions.c.id).where(_permissions.c.slug == slug)).first():
                continue
            conn.execute(
                sa.insert(_permissions).values(
                    id=uuid.uuid4(),
                    name=f"{resource.replace('_', ' ').title()} {action.title()}",
                    slug=slug,
                    resource=resource,
                    action=action,
                    description=f"Allows {action} on {resource.replace('_', ' ')}.",
                    created_at=now,
                )
            )

    perm_ids = {
        row.slug: row.id
        for row in conn.execute(sa.select(_permissions.c.id, _permissions.c.slug).where(_permissions.c.slug.in_(slugs)))
    }
    for role_slug in ("admin", "super_admin"):
        role = conn.execute(sa.select(_roles.c.id).where(_roles.c.slug == role_slug)).first()
        if role is None:
            continue
        for slug, perm_id in perm_ids.items():
            if role_slug == "admin" and slug in ADMIN_WITHHELD:
                continue
            exists = conn.execute(
                sa.select(_role_permissions.c.id).where(
                    _role_permissions.c.role_id == role.id, _role_permissions.c.permission_id == perm_id
                )
            ).first()
            if not exists:
                conn.execute(
                    sa.insert(_role_permissions).values(
                        id=uuid.uuid4(), role_id=role.id, permission_id=perm_id, granted_at=now
                    )
                )
