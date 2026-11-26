"""Align the migrated schema with the ORM models

Two earlier migrations disagree with the models, so a database built by
``alembic upgrade head`` rejected every graded answer and every vocabulary word:

- ``skilltype`` and ``part_of_speech_enum`` were created with lowercase labels,
  while SQLAlchemy stores the Python enum *names* (uppercase).
- ``exercise_attempts.metadata`` is ``attempt_metadata`` in the model.
- ``uq_vocab_word_pos`` was never created, so saving a word (``ON CONFLICT
  (word, part_of_speech)``) answered 500.

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

# Skipped with a warning when duplicates exist: merging words moves learners'
# review history and must not happen unattended inside a deploy.
ADD_VOCAB_UNIQUE = """
DO $$
BEGIN
    IF to_regclass('vocabulary_items') IS NULL OR EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = to_regclass('vocabulary_items') AND i.indisunique
          AND (
            SELECT array_agg(a.attname::text ORDER BY a.attname)
            FROM pg_attribute a
            WHERE a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
          ) = ARRAY['part_of_speech', 'word']
    ) THEN
        RETURN;
    END IF;
    IF EXISTS (
        SELECT 1 FROM vocabulary_items
        GROUP BY word, part_of_speech HAVING count(*) > 1
    ) THEN
        RAISE WARNING 'vocabulary_items has duplicate (word, part_of_speech) rows; uq_vocab_word_pos not created';
        RETURN;
    END IF;
    ALTER TABLE vocabulary_items
        ADD CONSTRAINT uq_vocab_word_pos UNIQUE (word, part_of_speech);
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
    op.execute(ADD_VOCAB_UNIQUE)


def downgrade() -> None:
    # The previous labels never worked with the models, so there is nothing
    # worth restoring.
    pass
