"""notifications.dedupe_key (one nudge per user, type, period) and the nurture email opt-out

Revision ID: f7a9b1c3d456
Revises: e6f8a0b2c345
Create Date: 2026-11-16
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "f7a9b1c3d456"
down_revision: str | None = "e6f8a0b2c345"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("notifications", sa.Column("dedupe_key", sa.String(80), nullable=True))
    op.create_index(
        "uq_notification_user_type_dedupe",
        "notifications",
        ["user_id", "type", "dedupe_key"],
        unique=True,
        postgresql_where=sa.text("dedupe_key IS NOT NULL"),
    )
    op.add_column(
        "user_reminder_preferences",
        sa.Column(
            "nurture_emails_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )


def downgrade() -> None:
    op.drop_column("user_reminder_preferences", "nurture_emails_enabled")
    op.drop_index("uq_notification_user_type_dedupe", table_name="notifications")
    op.drop_column("notifications", "dedupe_key")
