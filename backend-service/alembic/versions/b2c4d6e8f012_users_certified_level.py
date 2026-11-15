"""users.certified_level: the level a test confirmed, apart from the working level

`users.level` becomes the level a learner studies at (they may pick it); rank
and badges read `certified_level`, which only a test can raise.

Backfill keeps every rank where it is: the higher of the placement result and
the current level. Levels the old activity-driven promotion granted are kept.

Revision ID: b2c4d6e8f012
Revises: a1b3c5d7e901
Create Date: 2026-11-15
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "b2c4d6e8f012"
down_revision: str | None = "a1b3c5d7e901"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")


def _normalise(value: object) -> str | None:
    text = str(value or "").strip().upper()
    return text if text in _LEVELS else None


def upgrade() -> None:
    op.add_column("users", sa.Column("certified_level", sa.String(5), nullable=True))
    allowed = ", ".join(f"'{level}'" for level in _LEVELS)
    op.create_check_constraint(
        "ck_users_certified_level_cefr",
        "users",
        f"certified_level IS NULL OR certified_level IN ({allowed})",
    )

    bind = op.get_bind()
    rows = bind.execute(
        sa.text(
            "SELECT u.id, u.level, p.placement_level "
            "FROM users u LEFT JOIN user_proficiency_profiles p ON p.user_id = u.id"
        )
    ).fetchall()
    for user_id, level, placement in rows:
        candidates = [x for x in (_normalise(level), _normalise(placement)) if x]
        if not candidates:
            continue
        certified = max(candidates, key=_LEVELS.index)
        bind.execute(
            sa.text("UPDATE users SET certified_level = :level WHERE id = :id"),
            {"level": certified, "id": user_id},
        )


def downgrade() -> None:
    op.drop_constraint("ck_users_certified_level_cefr", "users", type_="check")
    op.drop_column("users", "certified_level")
