"""align an alembic-built schema with what the models write

Production was created by create_all, but a database built by `alembic upgrade
head` got lowercase labels for two enums the models store by member name, and a
`metadata` column the model calls `attempt_metadata`. There, every vocabulary
insert, skill write and exercise attempt failed. Each step is skipped when the
schema already matches, so this changes nothing on a create_all database.

Revision ID: e8b3a1c5d9f4
Revises: d7a2f5c1e9b3
Create Date: 2026-11-26 16:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e8b3a1c5d9f4"
down_revision: Union[str, None] = "d7a2f5c1e9b3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_ENUM_LABELS = {
    "part_of_speech_enum": (
        "noun", "verb", "adjective", "adverb", "pronoun",
        "preposition", "conjunction", "interjection", "phrase",
    ),
    "skilltype": (
        "vocabulary", "grammar", "reading", "listening", "speaking", "writing",
    ),
}


def upgrade() -> None:
    bind = op.get_bind()
    for enum_name, labels in _ENUM_LABELS.items():
        present = set(
            bind.execute(
                sa.text(
                    "SELECT e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid "
                    "WHERE t.typname = :name"
                ),
                {"name": enum_name},
            ).scalars()
        )
        for label in labels:
            if label in present and label.upper() not in present:
                op.execute(f"ALTER TYPE {enum_name} RENAME VALUE '{label}' TO '{label.upper()}'")

    columns = {c["name"] for c in sa.inspect(bind).get_columns("exercise_attempts")}
    if "metadata" in columns and "attempt_metadata" not in columns:
        op.alter_column("exercise_attempts", "metadata", new_column_name="attempt_metadata")


def downgrade() -> None:
    # Which schema a database started with is unknown here, and the models need
    # these names either way; reverting would break a create_all database.
    pass
