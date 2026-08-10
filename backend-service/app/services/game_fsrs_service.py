"""Best-effort FSRS updates for incorrect game answers."""

import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Union

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.vocabulary import VocabularyCRUD
from app.models.content import GrammarItem
from app.models.games import GameWord
from app.models.user_grammar_item import UserGrammarItem
from app.models.vocabulary import (
    UserVocabulary,
    VocabularyItem,
    VocabularyStatus,
)

logger = logging.getLogger(__name__)
_vocabulary_crud = VocabularyCRUD()

_SchedulableItem = Union[UserVocabulary, UserGrammarItem]

# Retry once on a unique-constraint race: two concurrent wrong answers for the
# same (user, concept) can both see "no row yet" and both attempt to insert.
_MAX_GET_OR_CREATE_ATTEMPTS = 2


def _apply_lapse(item: _SchedulableItem, *, now: datetime) -> tuple[float, int, int]:
    new_ease, new_interval, new_repetitions, _ = (
        _vocabulary_crud.calculate_next_review(
            quality=1,
            ease_factor=item.ease_factor or 2.5,
            interval=item.interval or 1,
            repetitions=item.repetitions or 0,
        )
    )
    fsrs_update = _vocabulary_crud.calculate_fsrs_review(
        quality=1,
        stability=item.fsrs_stability,
        difficulty=item.fsrs_difficulty,
        scheduled_days=item.fsrs_scheduled_days,
        reps=item.fsrs_reps,
        lapses=item.fsrs_lapses,
        fsrs_last_review=item.fsrs_last_review,
        sm2_last_review=item.last_reviewed_at,
        now=now,
    )

    item.ease_factor = new_ease
    item.interval = new_interval
    item.repetitions = new_repetitions
    item.next_review_date = fsrs_update["next_review_date"]
    item.last_reviewed_at = now
    for field in (
        "fsrs_stability",
        "fsrs_difficulty",
        "fsrs_elapsed_days",
        "fsrs_scheduled_days",
        "fsrs_reps",
        "fsrs_lapses",
        "fsrs_state",
        "fsrs_last_review",
    ):
        setattr(item, field, fsrs_update[field])
    item.total_reviews = (item.total_reviews or 0) + 1
    return new_ease, new_interval, new_repetitions


async def _get_or_create_vocabulary_row(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    vocabulary_id: uuid.UUID,
    now: datetime,
) -> UserVocabulary:
    result = await db.execute(
        select(UserVocabulary).where(
            UserVocabulary.user_id == user_id,
            UserVocabulary.vocabulary_id == vocabulary_id,
        )
    )
    user_vocabulary = result.scalar_one_or_none()
    if user_vocabulary is None:
        user_vocabulary = UserVocabulary(
            user_id=user_id,
            vocabulary_id=vocabulary_id,
            status=VocabularyStatus.LEARNING,
            ease_factor=2.5,
            interval=1,
            repetitions=0,
            next_review_date=now + timedelta(days=1),
            fsrs_stability=0.0,
            fsrs_difficulty=0.0,
            fsrs_elapsed_days=0,
            fsrs_scheduled_days=0,
            fsrs_reps=0,
            fsrs_lapses=0,
            fsrs_state=0,
            total_reviews=0,
            correct_reviews=0,
            streak=0,
            longest_streak=0,
            total_xp_earned=0,
            added_at=now,
        )
        db.add(user_vocabulary)
        await db.flush()  # surfaces a concurrent-insert IntegrityError here, not later
    return user_vocabulary


async def _get_or_create_grammar_row(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    grammar_item_id: uuid.UUID,
    now: datetime,
) -> UserGrammarItem:
    result = await db.execute(
        select(UserGrammarItem).where(
            UserGrammarItem.user_id == user_id,
            UserGrammarItem.grammar_item_id == grammar_item_id,
        )
    )
    user_grammar = result.scalar_one_or_none()
    if user_grammar is None:
        user_grammar = UserGrammarItem(
            user_id=user_id,
            grammar_item_id=grammar_item_id,
            ease_factor=2.5,
            interval=1,
            repetitions=0,
            next_review_date=now + timedelta(days=1),
            fsrs_stability=0.0,
            fsrs_difficulty=0.0,
            fsrs_elapsed_days=0,
            fsrs_scheduled_days=0,
            fsrs_reps=0,
            fsrs_lapses=0,
            fsrs_state=0,
            total_reviews=0,
            correct_reviews=0,
            added_at=now,
        )
        db.add(user_grammar)
        await db.flush()  # surfaces a concurrent-insert IntegrityError here, not later
    return user_grammar


async def record_game_vocab_lapse(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    game_word_id: str,
) -> None:
    """Resolve a game word and apply an incorrect vocabulary review."""
    try:
        parsed_game_word_id = uuid.UUID(str(game_word_id))
    except (TypeError, ValueError, AttributeError):
        return

    try:
        result = await db.execute(
            select(GameWord).where(GameWord.id == parsed_game_word_id)
        )
        game_word = result.scalar_one_or_none()
        if game_word is None:
            return

        result = await db.execute(
            select(VocabularyItem)
            .where(func.lower(VocabularyItem.word) == game_word.word.lower())
            .order_by(VocabularyItem.id)
            .limit(1)
        )
        vocabulary = result.scalar_one_or_none()
        if vocabulary is None:
            return

        for attempt in range(_MAX_GET_OR_CREATE_ATTEMPTS):
            try:
                async with db.begin_nested():
                    now = datetime.now(timezone.utc)
                    user_vocabulary = await _get_or_create_vocabulary_row(
                        db,
                        user_id=user_id,
                        vocabulary_id=vocabulary.id,
                        now=now,
                    )
                    new_ease, new_interval, new_repetitions = _apply_lapse(
                        user_vocabulary,
                        now=now,
                    )
                    user_vocabulary.status = _vocabulary_crud.determine_status(
                        new_ease,
                        new_interval,
                        new_repetitions,
                    )
                    user_vocabulary.streak = 0
                    await db.flush()
                return
            except IntegrityError:
                if attempt + 1 >= _MAX_GET_OR_CREATE_ATTEMPTS:
                    raise
                continue
    except Exception:
        logger.exception(
            "Failed to record game vocabulary lapse for user %s and word %s",
            user_id,
            game_word_id,
        )


async def record_game_grammar_lapse(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    topic: str,
) -> None:
    """Resolve a grammar topic and apply an incorrect grammar review."""
    if not topic:
        return

    try:
        result = await db.execute(
            select(GrammarItem)
            .where(func.lower(GrammarItem.topic) == topic.lower())
            .order_by(GrammarItem.id)
            .limit(1)
        )
        grammar_item = result.scalar_one_or_none()
        if grammar_item is None:
            return

        for attempt in range(_MAX_GET_OR_CREATE_ATTEMPTS):
            try:
                async with db.begin_nested():
                    now = datetime.now(timezone.utc)
                    user_grammar = await _get_or_create_grammar_row(
                        db,
                        user_id=user_id,
                        grammar_item_id=grammar_item.id,
                        now=now,
                    )
                    _apply_lapse(user_grammar, now=now)
                    await db.flush()
                return
            except IntegrityError:
                if attempt + 1 >= _MAX_GET_OR_CREATE_ATTEMPTS:
                    raise
                continue
    except Exception:
        logger.exception(
            "Failed to record game grammar lapse for user %s and topic %s",
            user_id,
            topic,
        )
