"""Align the migrated schema with the ORM models

Two earlier migrations disagree with the models, so a database built by
``alembic upgrade head`` rejected every graded answer and every vocabulary word:

- ``skilltype`` and ``part_of_speech_enum`` were created with lowercase labels,
  while SQLAlchemy stores the Python enum *names* (uppercase).
- ``exercise_attempts.metadata`` is ``attempt_metadata`` in the model.

Databases built with ``create_all`` already match, so every step is guarded and
does nothing there.

Revision ID: e9b4c2a7f1d8
Revises: e3b9c6a2f417
"""

from alembic import op

revision = "e9b4c2a7f1d8"
down_revision = "e3b9c6a2f417"
branch_labels = None
depends_on = None

ENUM_LABELS: dict[str, tuple[str, ...]] = {
    "skilltype": (
        "vocabulary",
        "grammar",
        "reading",
        "listening",
        "speaking",
        "writing",
    ),
    "part_of_speech_enum": (
        "noun",
        "verb",
        "adjective",
        "adverb",
        "pronoun",
        "preposition",
        "conjunction",
        "interjection",
        "phrase",
    ),
}

RENAME_LABEL = """
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = '{type}' AND e.enumlabel = '{old}'
          AND t.typnamespace = to_regnamespace(current_schema())
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = '{type}' AND e.enumlabel = '{new}'
          AND t.typnamespace = to_regnamespace(current_schema())
    ) THEN
        ALTER TYPE {type} RENAME VALUE '{old}' TO '{new}';
    END IF;
END $$
"""

RENAME_METADATA = """
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'exercise_attempts' AND column_name = 'metadata'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'exercise_attempts' AND column_name = 'attempt_metadata'
    ) THEN
        ALTER TABLE exercise_attempts RENAME COLUMN metadata TO attempt_metadata;
    END IF;
END $$
"""


def upgrade() -> None:
    if op.get_bind().dialect.name != "postgresql":
        return
    for type_name, labels in ENUM_LABELS.items():
        for label in labels:
            op.execute(
                RENAME_LABEL.format(type=type_name, old=label, new=label.upper())
            )
    op.execute(RENAME_METADATA)


def downgrade() -> None:
    # The previous labels never worked with the models, so there is nothing
    # worth restoring.
    pass
