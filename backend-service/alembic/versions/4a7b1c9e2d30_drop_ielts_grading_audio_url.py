"""drop the dead ielts_gradings.audio_url column

Speaking is graded from the Whisper transcript, so nothing ever wrote this
column. It shipped in d5e91f3a7c62 and had already run on production, so it
cannot be edited out of that migration — it is dropped here instead.

Revision ID: 4a7b1c9e2d30
Revises: d5e91f3a7c62
Create Date: 2026-08-21
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "4a7b1c9e2d30"
down_revision: Union[str, None] = "d5e91f3a7c62"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, None] = None


def _has_column() -> bool:
    inspector = sa.inspect(op.get_bind())
    if "ielts_gradings" not in inspector.get_table_names():
        return False
    return any(c["name"] == "audio_url" for c in inspector.get_columns("ielts_gradings"))


def upgrade() -> None:
    if _has_column():
        op.drop_column("ielts_gradings", "audio_url")


def downgrade() -> None:
    if not _has_column():
        op.add_column(
            "ielts_gradings", sa.Column("audio_url", sa.String(500), nullable=True)
        )
