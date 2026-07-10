"""add synced mistake notebook entries

Revision ID: add_mistake_notebook_entries
Revises: add_game_powerup_items
Create Date: 2026-07-03

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

from app.core.db_types import GUID, PortableJSON, TZDateTime


# revision identifiers, used by Alembic.
revision: str = "add_mistake_notebook_entries"
down_revision: Union[str, None] = "add_game_powerup_items"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "mistake_notebook_entries",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column(
            "user_id",
            GUID(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("client_id", sa.String(length=128), nullable=True),
        sa.Column("source_type", sa.String(length=80), nullable=False),
        sa.Column("source_id", sa.String(length=255), nullable=False),
        sa.Column("source_title", sa.String(length=500), nullable=False, server_default=""),
        sa.Column("question", sa.Text(), nullable=False),
        sa.Column("question_hash", sa.String(length=64), nullable=False),
        sa.Column("selected_answer", sa.Text(), nullable=False, server_default=""),
        sa.Column("correct_answer", sa.Text(), nullable=False, server_default=""),
        sa.Column("explanation", sa.Text(), nullable=False, server_default=""),
        sa.Column("skill", sa.String(length=80), nullable=False, server_default="general"),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="open"),
        sa.Column("review_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("extra_data", PortableJSON(), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("reviewed_at", TZDateTime(), nullable=True),
        sa.Column("last_seen_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint(
            "user_id",
            "client_id",
            name="uq_mistake_notebook_entries_user_client_id",
        ),
    )
    op.create_index(
        "ix_mistake_notebook_entries_user_id",
        "mistake_notebook_entries",
        ["user_id"],
    )
    op.create_index(
        "ix_mistake_notebook_entries_user_status_created",
        "mistake_notebook_entries",
        ["user_id", "status", "created_at"],
    )
    op.create_index(
        "ix_mistake_notebook_entries_user_source_question_hash",
        "mistake_notebook_entries",
        ["user_id", "source_type", "source_id", "question_hash"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_mistake_notebook_entries_user_source_question_hash",
        table_name="mistake_notebook_entries",
    )
    op.drop_index(
        "ix_mistake_notebook_entries_user_status_created",
        table_name="mistake_notebook_entries",
    )
    op.drop_index(
        "ix_mistake_notebook_entries_user_id",
        table_name="mistake_notebook_entries",
    )
    op.drop_table("mistake_notebook_entries")
