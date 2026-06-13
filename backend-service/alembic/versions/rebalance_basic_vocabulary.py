"""Rebalance and clean the 200-word starter vocabulary catalog.

Revision ID: rebalance_basic_vocabulary
Revises: new_user_starter_reward
Create Date: 2026-06-08
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op
from app.services.vocabulary_catalog_policy import (
    VocabularyCandidate,
    has_tag,
    is_placeholder_definition,
    normalize_all_tags,
    select_balanced_starter_vocabulary,
)

revision: str = "rebalance_basic_vocabulary"
down_revision: Union[str, None] = "new_user_starter_reward"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


UUID = postgresql.UUID(as_uuid=True)
JSON = postgresql.JSON()
vocabulary_status = postgresql.ENUM(
    "learning",
    "reviewing",
    "mastered",
    "archived",
    name="vocabulary_status_enum",
    create_type=False,
)

vocabulary_items = sa.table(
    "vocabulary_items",
    sa.column("id", UUID),
    sa.column("word", sa.String()),
    sa.column("definition", sa.Text()),
    sa.column("usage_frequency", sa.Integer()),
    sa.column("tags", JSON),
    sa.column("created_at", sa.DateTime(timezone=True)),
)
users = sa.table(
    "users",
    sa.column("id", UUID),
    sa.column("has_seeded_basic_words", sa.Boolean()),
)
user_vocabulary = sa.table(
    "user_vocabulary",
    sa.column("id", UUID),
    sa.column("user_id", UUID),
    sa.column("vocabulary_id", UUID),
    sa.column("status", vocabulary_status),
    sa.column("ease_factor", sa.Float()),
    sa.column("interval", sa.Integer()),
    sa.column("repetitions", sa.Integer()),
    sa.column("next_review_date", sa.DateTime(timezone=True)),
    sa.column("last_reviewed_at", sa.DateTime(timezone=True)),
    sa.column("fsrs_stability", sa.Float()),
    sa.column("fsrs_difficulty", sa.Float()),
    sa.column("fsrs_elapsed_days", sa.Integer()),
    sa.column("fsrs_scheduled_days", sa.Integer()),
    sa.column("fsrs_reps", sa.Integer()),
    sa.column("fsrs_lapses", sa.Integer()),
    sa.column("fsrs_state", sa.Integer()),
    sa.column("fsrs_last_review", sa.DateTime(timezone=True)),
    sa.column("total_reviews", sa.Integer()),
    sa.column("correct_reviews", sa.Integer()),
    sa.column("streak", sa.Integer()),
    sa.column("longest_streak", sa.Integer()),
    sa.column("total_xp_earned", sa.Integer()),
    sa.column("notes", sa.Text()),
    sa.column("added_at", sa.DateTime(timezone=True)),
)
vocabulary_reviews = sa.table(
    "vocabulary_reviews",
    sa.column("user_vocabulary_id", UUID),
)
vocabulary_deck_items = sa.table(
    "vocabulary_deck_items",
    sa.column("user_vocabulary_id", UUID),
)


def _load_catalog(connection) -> list[dict]:
    return list(
        connection.execute(
            sa.select(
                vocabulary_items.c.id,
                vocabulary_items.c.word,
                vocabulary_items.c.definition,
                vocabulary_items.c.usage_frequency,
                vocabulary_items.c.tags,
                vocabulary_items.c.created_at,
            )
        ).mappings()
    )


def _retag_catalog(connection, catalog: list[dict]) -> tuple[set, set]:
    assignments = select_balanced_starter_vocabulary(
        VocabularyCandidate(
            id=row["id"],
            word=row["word"],
            definition=row["definition"],
            usage_frequency=row["usage_frequency"] or 0,
            tags=row["tags"],
            created_at=row["created_at"],
        )
        for row in catalog
    )
    selected_topics = {
        assignment.candidate.id: assignment.topic for assignment in assignments
    }
    old_basic_ids = {row["id"] for row in catalog if has_tag(row["tags"], "basic_200")}

    for row in catalog:
        tags = [tag for tag in normalize_all_tags(row["tags"]) if tag != "basic_200"]
        selected_topic = selected_topics.get(row["id"])
        if selected_topic:
            if selected_topic not in tags:
                tags.append(selected_topic)
            tags.append("basic_200")
        connection.execute(
            sa.update(vocabulary_items)
            .where(vocabulary_items.c.id == row["id"])
            .values(tags=tags)
        )

    return old_basic_ids, set(selected_topics)


def _remove_unreviewed_obsolete_rows(
    connection,
    catalog: list[dict],
    old_basic_ids: set,
    selected_ids: set,
) -> None:
    placeholder_ids = {
        row["id"] for row in catalog if is_placeholder_definition(row["definition"])
    }
    removable_vocabulary_ids = placeholder_ids | (old_basic_ids - selected_ids)
    if not removable_vocabulary_ids:
        return

    has_review = sa.exists(
        sa.select(1).where(
            vocabulary_reviews.c.user_vocabulary_id == user_vocabulary.c.id
        )
    )
    is_in_custom_deck = sa.exists(
        sa.select(1).where(
            vocabulary_deck_items.c.user_vocabulary_id == user_vocabulary.c.id
        )
    )
    connection.execute(
        sa.delete(user_vocabulary).where(
            user_vocabulary.c.vocabulary_id.in_(removable_vocabulary_ids),
            user_vocabulary.c.total_reviews == 0,
            ~has_review,
            ~is_in_custom_deck,
        )
    )


def _starter_row(user_id, vocabulary_id, now: datetime) -> dict:
    return {
        "id": uuid.uuid4(),
        "user_id": user_id,
        "vocabulary_id": vocabulary_id,
        "status": "learning",
        "ease_factor": 2.5,
        "interval": 1,
        "repetitions": 0,
        "next_review_date": now + timedelta(days=1),
        "last_reviewed_at": None,
        "fsrs_stability": 0.0,
        "fsrs_difficulty": 0.0,
        "fsrs_elapsed_days": 0,
        "fsrs_scheduled_days": 0,
        "fsrs_reps": 0,
        "fsrs_lapses": 0,
        "fsrs_state": 0,
        "fsrs_last_review": None,
        "total_reviews": 0,
        "correct_reviews": 0,
        "streak": 0,
        "longest_streak": 0,
        "total_xp_earned": 0,
        "notes": None,
        "added_at": now,
    }


def _seed_existing_users(connection, selected_ids: set) -> None:
    selected_id_list = list(selected_ids)
    user_ids = list(
        connection.execute(
            sa.select(users.c.id).where(users.c.has_seeded_basic_words.is_(True))
        ).scalars()
    )
    now = datetime.now(timezone.utc)

    for start in range(0, len(user_ids), 100):
        batch_user_ids = user_ids[start : start + 100]
        existing_pairs = set(
            connection.execute(
                sa.select(
                    user_vocabulary.c.user_id,
                    user_vocabulary.c.vocabulary_id,
                ).where(
                    user_vocabulary.c.user_id.in_(batch_user_ids),
                    user_vocabulary.c.vocabulary_id.in_(selected_id_list),
                )
            ).tuples()
        )
        rows = [
            _starter_row(user_id, vocabulary_id, now)
            for user_id in batch_user_ids
            for vocabulary_id in selected_id_list
            if (user_id, vocabulary_id) not in existing_pairs
        ]
        for row_start in range(0, len(rows), 1000):
            connection.execute(
                sa.insert(user_vocabulary),
                rows[row_start : row_start + 1000],
            )


def upgrade() -> None:
    connection = op.get_bind()
    catalog = _load_catalog(connection)
    old_basic_ids, selected_ids = _retag_catalog(connection, catalog)
    _remove_unreviewed_obsolete_rows(
        connection,
        catalog,
        old_basic_ids,
        selected_ids,
    )
    _seed_existing_users(connection, selected_ids)


def downgrade() -> None:
    # This cleanup intentionally preserves the repaired catalog and user data.
    # Reconstructing the malformed starter set would reintroduce placeholders.
    pass
