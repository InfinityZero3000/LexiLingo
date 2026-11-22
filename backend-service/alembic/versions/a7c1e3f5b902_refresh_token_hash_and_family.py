"""refresh_tokens: store a sha256 of the token, group rotations into families

Revision ID: a7c1e3f5b902
Revises: f7a9b1c3d456
Create Date: 2026-11-16
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "a7c1e3f5b902"
down_revision: str | None = "f7a9b1c3d456"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("refresh_tokens", sa.Column("token_hash", sa.String(64), nullable=True))
    op.add_column("refresh_tokens", sa.Column("family_id", sa.Uuid(), nullable=True))
    op.add_column("refresh_tokens", sa.Column("rotated_at", sa.DateTime(timezone=True), nullable=True))
    # The raw column stays for one release so a rollback keeps working; new rows leave it empty.
    op.alter_column("refresh_tokens", "token", existing_type=sa.String(500), nullable=True)

    op.execute(
        "UPDATE refresh_tokens "
        "SET token_hash = encode(sha256(convert_to(token, 'UTF8')), 'hex'), "
        "family_id = gen_random_uuid() "
        "WHERE token IS NOT NULL"
    )

    op.create_index("ix_refresh_tokens_token_hash", "refresh_tokens", ["token_hash"], unique=True)
    op.create_index("ix_refresh_tokens_family_id", "refresh_tokens", ["family_id"])


def downgrade() -> None:
    op.drop_index("ix_refresh_tokens_family_id", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_token_hash", table_name="refresh_tokens")
    # Rows written after the upgrade have no raw value; they cannot satisfy NOT NULL.
    op.execute("DELETE FROM refresh_tokens WHERE token IS NULL")
    op.alter_column("refresh_tokens", "token", existing_type=sa.String(500), nullable=False)
    op.drop_column("refresh_tokens", "rotated_at")
    op.drop_column("refresh_tokens", "family_id")
    op.drop_column("refresh_tokens", "token_hash")
