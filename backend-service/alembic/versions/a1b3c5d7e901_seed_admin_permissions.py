"""seed admin permissions

Gives the admin role exactly what admin routes allowed before permissions were
enforced, so nothing changes for anyone on deploy. Idempotent.

Revision ID: a1b3c5d7e901
Revises: f4a6b8c0d123
Create Date: 2026-11-10
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

from app.services.permission_seed import seed_permissions

revision: str = "a1b3c5d7e901"
down_revision: str | None = "f4a6b8c0d123"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

CRUD = ["create", "read", "update", "delete"]
# Frozen copy: a later catalog change must not rewrite what this migration did.
CATALOG = {
    "courses": CRUD + ["manage"],
    "content": CRUD,
    "achievements": CRUD,
    "shop": CRUD,
    "ielts": CRUD,
    "banners": CRUD,
    "categories": CRUD,
    "topics": CRUD,
    "notifications": CRUD,
    "ranking": CRUD,
    "content_agent": CRUD,
    "users": ["read", "update", "delete", "manage"],
    "gifts": ["read", "grant"],
    "analytics": ["read"],
    "ops": ["read"],
    "rbac": ["read", "manage"],
}


def upgrade() -> None:
    seed_permissions(op.get_bind(), CATALOG)


def downgrade() -> None:
    # Permissions may have been edited by operators since; leave them in place.
    pass
