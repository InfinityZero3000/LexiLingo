"""Add provenance-v2 fields and upload ownership columns.

Revision ID: add_content_provenance_v2
Revises: add_cefr_content_agent
Create Date: 2026-06-15

All new columns are nullable so existing rows remain valid (backward-compatible).
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.core.db_types import TZDateTime

revision: str = "add_content_provenance_v2"
down_revision: str = "add_cefr_content_agent"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # ContentProvenance — v2 provenance fields
    with op.batch_alter_table("content_provenance") as batch_op:
        batch_op.add_column(
            sa.Column("source_version", sa.String(length=64), nullable=True)
        )
        batch_op.add_column(
            sa.Column("license_id", sa.String(length=128), nullable=True)
        )
        batch_op.add_column(
            sa.Column("license_url", sa.String(length=1000), nullable=True)
        )
        batch_op.add_column(
            sa.Column("attribution_text", sa.Text(), nullable=True)
        )
        batch_op.add_column(
            sa.Column("raw_checksum", sa.String(length=64), nullable=True)
        )
        batch_op.add_column(
            sa.Column("record_checksum", sa.String(length=64), nullable=True)
        )
        batch_op.add_column(
            sa.Column("lineage", sa.JSON(), nullable=True)
        )
        batch_op.add_column(
            sa.Column("content_usage", sa.String(length=32), nullable=True)
        )
        batch_op.add_column(
            sa.Column("rights_confirmed_at", TZDateTime(), nullable=True)
        )
        batch_op.add_column(
            sa.Column("rights_statement_version", sa.String(length=32), nullable=True)
        )

    # ContentAgentUpload — v2 ownership fields
    with op.batch_alter_table("content_agent_uploads") as batch_op:
        batch_op.add_column(
            sa.Column("rights_confirmed", sa.Boolean(), nullable=False,
                      server_default=sa.text("false"))
        )
        batch_op.add_column(
            sa.Column("rights_confirmed_at", TZDateTime(), nullable=True)
        )
        batch_op.add_column(
            sa.Column("uploader_id", sa.Uuid(), nullable=True)
        )


def downgrade() -> None:
    with op.batch_alter_table("content_agent_uploads") as batch_op:
        batch_op.drop_column("uploader_id")
        batch_op.drop_column("rights_confirmed_at")
        batch_op.drop_column("rights_confirmed")

    with op.batch_alter_table("content_provenance") as batch_op:
        batch_op.drop_column("rights_statement_version")
        batch_op.drop_column("rights_confirmed_at")
        batch_op.drop_column("content_usage")
        batch_op.drop_column("lineage")
        batch_op.drop_column("record_checksum")
        batch_op.drop_column("raw_checksum")
        batch_op.drop_column("attribution_text")
        batch_op.drop_column("license_url")
        batch_op.drop_column("license_id")
        batch_op.drop_column("source_version")
