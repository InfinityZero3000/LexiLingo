"""vocabulary_items lower(word) index; user_vocabulary re-save tracking

Revision ID: c4e8a1b7d3f6
Revises: b3d5f7a9c1e2
Create Date: 2026-11-17
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "c4e8a1b7d3f6"
down_revision: str | None = "b3d5f7a9c1e2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    dupes = bind.execute(
        sa.text(
            "SELECT lower(word) AS w, count(*) AS n FROM vocabulary_items "
            "GROUP BY lower(word) HAVING count(*) > 1 ORDER BY n DESC LIMIT 10"
        )
    ).all()
    if dupes:
        sample = ", ".join(f"{row.w!r} x{row.n}" for row in dupes)
        raise RuntimeError(
            "vocabulary_items has words that differ only by case; merge them before "
            f"migrating (first {len(dupes)}): {sample}"
        )
    op.execute("CREATE INDEX IF NOT EXISTS ix_vocabulary_items_lower_word ON vocabulary_items (lower(word))")
    # The plain index on word was never used by the lower(word) lookup; uq_vocab_word_pos covers exact-word scans.
    op.execute("DROP INDEX IF EXISTS ix_vocabulary_items_word_lower")
    op.add_column(
        "user_vocabulary",
        sa.Column("resave_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column("user_vocabulary", sa.Column("last_resaved_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    op.drop_column("user_vocabulary", "last_resaved_at")
    op.drop_column("user_vocabulary", "resave_count")
    op.execute("CREATE INDEX IF NOT EXISTS ix_vocabulary_items_word_lower ON vocabulary_items (word)")
    op.execute("DROP INDEX IF EXISTS ix_vocabulary_items_lower_word")
