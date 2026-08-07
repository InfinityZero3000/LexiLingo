"""add partner_api_keys table, migrate legacy static-hash keys

Revision ID: add_partner_api_keys
Revises: content_cefr_level_checks
Create Date: 2026-08-07
"""

from __future__ import annotations

import os
import uuid
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.core.db_types import GUID, TZDateTime

revision: str = "add_partner_api_keys"
down_revision: str | None = "content_cefr_level_checks"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "partner_api_keys",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("key_id", sa.String(20), nullable=False, unique=True),
        sa.Column("key_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("owner", sa.String(255), nullable=False),
        sa.Column("scope", sa.String(50), nullable=False, server_default="read"),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("expires_at", TZDateTime(), nullable=True),
        sa.Column("revoked_at", TZDateTime(), nullable=True),
    )

    # Migrate keys from the old LEXILINGO_PARTNER_API_KEY_HASHES env var (a
    # comma-separated static hash list) into rows here, so partners using an
    # already-issued key aren't locked out by this migration. Owner/scope are
    # placeholders — replace them with the real partner identity once known.
    legacy_hashes = [
        value.strip().lower()
        for value in os.environ.get("LEXILINGO_PARTNER_API_KEY_HASHES", "").split(",")
        if value.strip()
    ]
    if legacy_hashes:
        table = sa.table(
            "partner_api_keys",
            sa.column("id", GUID()),
            sa.column("key_id", sa.String()),
            sa.column("key_hash", sa.String()),
            sa.column("owner", sa.String()),
            sa.column("scope", sa.String()),
        )
        op.bulk_insert(
            table,
            [
                {
                    "id": uuid.uuid4(),
                    "key_id": f"legacy-{i}",
                    "key_hash": key_hash,
                    "owner": "unknown-legacy-partner",
                    "scope": "read",
                }
                for i, key_hash in enumerate(legacy_hashes, start=1)
            ],
        )


def downgrade() -> None:
    op.drop_table("partner_api_keys")
