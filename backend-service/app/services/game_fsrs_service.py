"""Best-effort learner-state updates for incorrect game answers."""

import hashlib
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Union

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.vocabulary import VocabularyCRUD, _vocab_concept_id
from app.models.content import GrammarItem
from app.models.games import GameWord
from app.models.learner_state import (
    LearnerConceptState,
    LearnerObservationEvent,
)
from app.models.user_grammar_item import UserGrammarItem
from app.models.vocabulary import (
    UserVocabulary,
    VocabularyItem,
    VocabularyStatus,
)
from app.services.learner_state import (
    ObservationInput,
    apply_observation_event,
    grade_to_observation,
    ingest_observations,
)

logger = logging.getLogger(__name__)
_vocabulary_crud = VocabularyCRUD()

_SchedulableItem = Union[UserVocabulary, UserGrammarItem]

# Retry once on a unique-constraint race: two concurrent wrong answers for the
# same (user, concept) can both see "no row yet" and both attempt to insert.
_MAX_GET_OR_CREATE_ATTEMPTS = 2

# A missed game answer is a lapse, but a softer signal than a failed review:
# games are timed and partly luck, so it must not carry blackout weight.
GAME_LAPSE_QUALITY = 1


def _grammar_concept_id(topic: str) -> str:
    """Mirror of :func:`_vocab_concept_id`'s slug convention for grammar."""
    return f"grammar:{'_'.join(topic.strip().lower().split())}"


async def _apply_lapse(
    db: AsyncSession,
    item: _SchedulableItem,
    *,
    user_id: uuid.UUID,
    concept_id: str,
    now: datetime,
) -> LearnerConceptState | None:
    """Record the lapse through the unified learner-state engine.

    This used to run its own SM-2 + FSRS-lite pass and write the legacy
    ease/interval/fsrs_* columns directly, which made game answers and
    vocabulary reviews schedule the same word by two different algorithms —
    whichever ran last won. Scheduling now has a single owner; the legacy
    columns stay frozen as history, exactly as submit_review leaves them.
    """
    outcome, confidence = grade_to_observation(GAME_LAPSE_QUALITY)
    event_id = hashlib.sha256(
        f"game:{user_id}:{concept_id}:{now.isoformat()}".encode()
    ).hexdigest()

    await ingest_observations(
        db,
        [
            ObservationInput(
                event_id=event_id,
                user_id=user_id,
                concept_id=concept_id,
                outcome=outcome,
                confidence=confidence,
                observed_at=now,
            )
        ],
    )
    event_db_id = await db.scalar(
        select(LearnerObservationEvent.id).where(
            LearnerObservationEvent.event_id == event_id
        )
    )
    await apply_observation_event(db, event_db_id, now=now)
    concept_state = await db.scalar(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == user_id,
            LearnerConceptState.concept_id == concept_id,
        )
    )

    # Keep the row usable as a read-cache for the existing due-list queries.
    if concept_state is not None:
        item.next_review_date = concept_state.next_review_at
    item.last_reviewed_at = now
    item.total_reviews = (item.total_reviews or 0) + 1
    return concept_state


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
                    concept_state = await _apply_lapse(
                        db,
                        user_vocabulary,
                        user_id=user_id,
                        concept_id=_vocab_concept_id(vocabulary.word),
                        now=now,
                    )
                    if concept_state is not None:
                        user_vocabulary.status = (
                            _vocabulary_crud.determine_status_from_mastery(
                                concept_state.mastery_probability,
                                concept_state.attempt_count,
                                concept_state.stability_days,
                            )
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
                    await _apply_lapse(
                        db,
                        user_grammar,
                        user_id=user_id,
                        concept_id=_grammar_concept_id(grammar_item.topic),
                        now=now,
                    )
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
