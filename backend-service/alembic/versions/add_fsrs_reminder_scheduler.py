"""add fsrs reminder scheduler

Revision ID: add_fsrs_reminder_scheduler
Revises: fix_badge_cdn_urls
Create Date: 2026-06-01

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.core.db_types import GUID, PortableJSON, TZDateTime


# revision identifiers, used by Alembic.
revision: str = "add_fsrs_reminder_scheduler"
down_revision: Union[str, None] = "fix_badge_cdn_urls"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_reminder_preferences",
        sa.Column(
            "user_id",
            GUID(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("push_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("email_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("reminder_time_local", sa.String(length=5), nullable=False, server_default="09:00"),
        sa.Column(
            "timezone",
            sa.String(length=64),
            nullable=False,
            server_default="Asia/Ho_Chi_Minh",
        ),
        sa.Column("min_due_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("email_cadence_days", sa.Integer(), nullable=False, server_default="7"),
        sa.Column("next_check_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("last_push_sent_at", TZDateTime(), nullable=True),
        sa.Column("last_email_sent_at", TZDateTime(), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index(
        "ix_user_reminder_preferences_enabled_next",
        "user_reminder_preferences",
        ["enabled", "next_check_at"],
    )
    op.create_index(
        "ix_user_reminder_preferences_next_check_at",
        "user_reminder_preferences",
        ["next_check_at"],
    )

    op.create_table(
        "reminder_deliveries",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column(
            "user_id",
            GUID(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("channel", sa.String(length=20), nullable=False),
        sa.Column(
            "reminder_type",
            sa.String(length=50),
            nullable=False,
            server_default="vocabulary_review",
        ),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="queued"),
        sa.Column("due_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("dedupe_key", sa.String(length=180), nullable=False),
        sa.Column("scheduled_for", TZDateTime(), nullable=False),
        sa.Column("sent_at", TZDateTime(), nullable=True),
        sa.Column("error", sa.String(length=1000), nullable=True),
        sa.Column("data", PortableJSON(), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("dedupe_key", name="uq_reminder_deliveries_dedupe_key"),
    )
    op.create_index("ix_reminder_deliveries_user_id", "reminder_deliveries", ["user_id"])
    op.create_index(
        "ix_reminder_deliveries_scheduled_for",
        "reminder_deliveries",
        ["scheduled_for"],
    )
    op.create_index(
        "ix_reminder_delivery_user_channel_created",
        "reminder_deliveries",
        ["user_id", "channel", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_reminder_delivery_user_channel_created", table_name="reminder_deliveries")
    op.drop_index("ix_reminder_deliveries_scheduled_for", table_name="reminder_deliveries")
    op.drop_index("ix_reminder_deliveries_user_id", table_name="reminder_deliveries")
    op.drop_table("reminder_deliveries")
    op.drop_index(
        "ix_user_reminder_preferences_next_check_at",
        table_name="user_reminder_preferences",
    )
    op.drop_index(
        "ix_user_reminder_preferences_enabled_next",
        table_name="user_reminder_preferences",
    )
    op.drop_table("user_reminder_preferences")
