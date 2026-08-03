"""backfill learner_concept_states from existing UserVocabulary SM-2/FSRS state

Revision ID: backfill_vocab_lcs
Revises: add_lesson_outcome
Create Date: 2026-08-03

Maps each UserVocabulary row to a LearnerConceptState row so vocabulary
mastery tracking is unified with the general concept-state engine used for
grammar/mission exercises. concept_id is derived from the WORD TEXT (not the
vocabulary_item UUID) so it matches the same slug convention used by the
content-agent generator (`vocab:<word_lower_with_underscores>`) — this is
what lets a word learned via flashcard and the same word encountered in a
lesson exercise contribute to the same mastery row.

Does not touch or drop any UserVocabulary column (rollback-safe); those
columns become read-only history after app/crud/vocabulary.py stops writing
to them in a later change.
"""

import re
import uuid
from datetime import datetime, timezone

import sqlalchemy as sa
from alembic import op

revision: str = "backfill_vocab_lcs"
down_revision: str | None = "add_lesson_outcome"
branch_labels = None
depends_on = None


def _slug(word: str) -> str:
    return "_".join(word.strip().lower().split())


def upgrade() -> None:
    connection = op.get_bind()

    rows = connection.execute(
        sa.text(
            """
            SELECT
                uv.user_id AS user_id,
                vi.word AS word,
                uv.ease_factor AS ease_factor,
                uv.fsrs_stability AS fsrs_stability,
                uv.fsrs_difficulty AS fsrs_difficulty,
                uv.next_review_date AS next_review_date,
                uv.last_reviewed_at AS last_reviewed_at,
                uv.total_reviews AS total_reviews,
                uv.correct_reviews AS correct_reviews
            FROM user_vocabulary uv
            JOIN vocabulary_items vi ON vi.id = uv.vocabulary_id
            WHERE vi.word IS NOT NULL AND vi.word != ''
            """
        )
    ).fetchall()

    if not rows:
        return

    # This migration writes via raw SQL, bypassing the ORM's TZDateTime
    # TypeDecorator (app/core/db_types.py) that normally strips tzinfo before
    # binding — asyncpg rejects timezone-aware datetimes against the
    # TIMESTAMP WITHOUT TIME ZONE columns these tables actually use.
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    insert_stmt = sa.text(
        """
        INSERT INTO learner_concept_states (
            id, user_id, concept_id, mastery_probability, stability_days,
            difficulty, attempt_count, correct_count, error_count,
            last_interacted_at, next_review_at, state_version,
            algorithm_version, created_at, updated_at
        ) VALUES (
            :id, :user_id, :concept_id, :mastery_probability, :stability_days,
            :difficulty, :attempt_count, :correct_count, :error_count,
            :last_interacted_at, :next_review_at, 1,
            'bkt-fsrs-v1', :created_at, :updated_at
        )
        ON CONFLICT (user_id, concept_id) DO NOTHING
        """
    )

    for row in rows:
        slug = _slug(row.word)
        if not slug:
            continue
        ease_factor = row.ease_factor if row.ease_factor is not None else 2.5
        mastery = (ease_factor - 1.3) / (3.0 - 1.3)
        mastery = max(0.01, min(0.99, mastery))
        stability = max(0.25, row.fsrs_stability or 0.25)
        difficulty = max(0.0, min(1.0, (row.fsrs_difficulty or 5.0) / 10.0))
        total = row.total_reviews or 0
        correct = min(row.correct_reviews or 0, total)

        connection.execute(
            insert_stmt,
            {
                "id": uuid.uuid4(),
                "user_id": row.user_id,
                "concept_id": f"vocab:{slug}",
                "mastery_probability": mastery,
                "stability_days": stability,
                "difficulty": difficulty,
                "attempt_count": total,
                "correct_count": correct,
                "error_count": total - correct,
                "last_interacted_at": row.last_reviewed_at,
                "next_review_at": row.next_review_date,
                "created_at": now,
                "updated_at": now,
            },
        )


def downgrade() -> None:
    # Intentional no-op: this is a data backfill, not a schema change, and
    # rows created here are indistinguishable from real reviews recorded
    # after this migration ran. Deleting by concept_id prefix would risk
    # destroying genuine user progress. UserVocabulary's own SM-2/FSRS
    # columns are untouched, so the pre-migration read path still works if
    # app code is rolled back alongside this migration.
    pass
