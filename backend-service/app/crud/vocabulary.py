"""
Vocabulary CRUD Operations
Phase 3: Spaced Repetition System with SuperMemo SM-2 Algorithm
"""

import hashlib
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING, List, Optional

from sqlalchemy import and_, func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

if TYPE_CHECKING:
    from app.models.user import User


from app.models.content_agent import LessonVocabularyItem
from app.models.course import Lesson
from app.models.learner_state import LearnerConceptState, LearnerObservationEvent
from app.models.vocabulary import (
    DifficultyLevel,
    PartOfSpeech,
    UserVocabulary,
    VocabularyDeck,
    VocabularyDeckItem,
    VocabularyItem,
    VocabularyReview,
    VocabularyStatus,
)
from app.services.learner_state import (
    ObservationInput,
    apply_observation_event,
    grade_to_observation,
    ingest_observations,
)


# A word counts as mastered only once recall is both confident and durable;
# 21 days is the interval bar the pre-unification SM-2 status used.
MASTERED_MASTERY = 0.85
MASTERED_STABILITY_DAYS = 21.0


def _vocab_concept_id(word: str) -> str:
    """Slug convention shared (by duplication, not import) with
    ai-service's content-agent generator and the vocab->concept-state
    backfill migration — keep all three in sync if this ever changes."""
    return f"vocab:{'_'.join(word.strip().lower().split())}"
from app.services.vocabulary_catalog_policy import (
    VocabularyCandidate,
    canonical_topic,
    has_tag,
    is_placeholder_definition,
    normalize_all_tags,
    select_balanced_starter_vocabulary,
)

_PLACEHOLDER_DEFINITION_VALUES = (
    "",
    "#n/a",
    "#n/a yet",
    "n/a",
    "n/a yet",
    "n.a.",
    "not available",
    "not available yet",
    "unknown",
    "tbd",
    "todo",
    "---",
)


def _valid_definition_conditions():
    return (
        VocabularyItem.definition.is_not(None),
        func.lower(func.trim(VocabularyItem.definition)).notin_(
            _PLACEHOLDER_DEFINITION_VALUES
        ),
    )


class VocabularyCRUD:
    """CRUD operations for vocabulary management"""

    def normalize_word(self, word: str) -> str:
        """Normalize user-selected text for stable vocabulary lookup/creation."""
        cleaned = re.sub(r"[^a-zA-Z0-9'\-\s]", "", (word or "").strip().lower())
        cleaned = re.sub(r"\s+", " ", cleaned).strip()
        return cleaned
    
    # ===== VocabularyItem CRUD =====
    
    async def get_vocabulary_item(
        self,
        db: AsyncSession,
        vocabulary_id: uuid.UUID
    ) -> Optional[VocabularyItem]:
        """Get vocabulary item by ID"""
        result = await db.execute(
            select(VocabularyItem).where(VocabularyItem.id == vocabulary_id)
        )
        return result.scalar_one_or_none()
    
    async def get_vocabulary_items(
        self,
        db: AsyncSession,
        course_id: Optional[uuid.UUID] = None,
        lesson_id: Optional[uuid.UUID] = None,
        difficulty_level: Optional[str] = None,
        tag: Optional[str] = None,
        limit: int = 50,
        offset: int = 0
    ) -> List[VocabularyItem]:
        """Get vocabulary items with filters"""
        query = select(VocabularyItem)
        
        conditions = []
        if course_id:
            course_memberships = (
                select(LessonVocabularyItem.vocabulary_id)
                .join(Lesson, Lesson.id == LessonVocabularyItem.lesson_id)
                .where(Lesson.course_id == course_id)
            )
            conditions.append(
                or_(
                    VocabularyItem.course_id == course_id,
                    VocabularyItem.id.in_(course_memberships),
                )
            )
        if lesson_id:
            lesson_memberships = select(
                LessonVocabularyItem.vocabulary_id
            ).where(LessonVocabularyItem.lesson_id == lesson_id)
            conditions.append(
                or_(
                    VocabularyItem.lesson_id == lesson_id,
                    VocabularyItem.id.in_(lesson_memberships),
                )
            )
        if difficulty_level:
            conditions.append(VocabularyItem.difficulty_level == difficulty_level)
        conditions.extend(_valid_definition_conditions())
        
        if conditions:
            query = query.where(and_(*conditions))

        query = query.order_by(
            VocabularyItem.usage_frequency.desc().nullslast(),
            VocabularyItem.created_at,
            func.lower(VocabularyItem.word),
            VocabularyItem.id,
        )

        if not tag:
            query = query.offset(offset).limit(limit)

        result = await db.execute(query)
        items = [
            item
            for item in result.scalars().all()
            if not is_placeholder_definition(item.definition)
        ]
        if tag:
            expected_tag = canonical_topic(tag)
            items = [
                item
                for item in items
                if expected_tag in normalize_all_tags(item.tags)
            ]
            return items[offset : offset + limit]
        return items
    
    async def search_vocabulary(
        self,
        db: AsyncSession,
        search_term: str,
        limit: int = 20
    ) -> List[VocabularyItem]:
        """Search vocabulary by word (case-insensitive)"""
        query = select(VocabularyItem).where(
            VocabularyItem.word.ilike(f"%{search_term}%"),
            *_valid_definition_conditions(),
        ).limit(limit).order_by(VocabularyItem.word)
        
        result = await db.execute(query)
        return [
            item
            for item in result.scalars().all()
            if not is_placeholder_definition(item.definition)
        ]

    async def find_vocabulary_by_word(
        self,
        db: AsyncSession,
        word: str,
    ) -> Optional[VocabularyItem]:
        """Find vocabulary item by normalized exact word match."""
        normalized = self.normalize_word(word)
        if not normalized:
            return None

        result = await db.execute(
            select(VocabularyItem)
            .where(func.lower(VocabularyItem.word) == normalized)
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def create_vocabulary_item(
        self,
        db: AsyncSession,
        word: str,
        definition: Optional[str] = None,
        translation: Optional[str] = None,
        part_of_speech: Optional[str] = None,
        difficulty_level: Optional[str] = None,
    ) -> VocabularyItem:
        """Create a master vocabulary item for user-discovered words."""
        normalized = self.normalize_word(word)
        if not normalized:
            raise ValueError("Invalid word")

        allowed_pos = {item.value for item in PartOfSpeech}
        pos = (part_of_speech or PartOfSpeech.NOUN.value).lower()
        if pos not in allowed_pos:
            pos = PartOfSpeech.NOUN.value

        allowed_levels = {item.value for item in DifficultyLevel}
        level = (difficulty_level or DifficultyLevel.A1.value).upper()
        if level not in allowed_levels:
            level = DifficultyLevel.A1.value

        item = VocabularyItem(
            word=normalized,
            definition=(definition or f"A user-saved word: {normalized}").strip(),
            translation={"vi": translation.strip()} if translation and translation.strip() else None,
            part_of_speech=pos,
            difficulty_level=level,
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)
        return item
    
    # ===== UserVocabulary CRUD =====
    
    async def get_user_vocabulary(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        vocabulary_id: uuid.UUID
    ) -> Optional[UserVocabulary]:
        """Get user's vocabulary entry"""
        result = await db.execute(
            select(UserVocabulary).where(
                and_(
                    UserVocabulary.user_id == user_id,
                    UserVocabulary.vocabulary_id == vocabulary_id
                )
            )
        )
        return result.scalar_one_or_none()
    
    async def get_user_vocabulary_list(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        status: Optional[VocabularyStatus] = None,
        limit: int = 50,
        offset: int = 0
    ) -> List[UserVocabulary]:
        """Get user's vocabulary collection with vocabulary items eager-loaded."""
        query = (
            select(UserVocabulary)
            .options(joinedload(UserVocabulary.vocabulary))  # avoid N+1
            .join(
                VocabularyItem,
                VocabularyItem.id == UserVocabulary.vocabulary_id,
            )
            .where(UserVocabulary.user_id == user_id)
            .where(*_valid_definition_conditions())
        )

        if status:
            query = query.where(UserVocabulary.status == status)

        query = query.limit(limit).offset(offset).order_by(UserVocabulary.added_at.desc())

        result = await db.execute(query)
        return list(result.scalars().all())

    async def count_user_vocabulary(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        status: Optional[VocabularyStatus] = None,
    ) -> int:
        """Count visible vocabulary entries in a user's collection."""
        query = (
            select(func.count(UserVocabulary.id))
            .join(
                VocabularyItem,
                VocabularyItem.id == UserVocabulary.vocabulary_id,
            )
            .where(UserVocabulary.user_id == user_id)
            .where(*_valid_definition_conditions())
        )

        if status:
            query = query.where(UserVocabulary.status == status)

        result = await db.execute(query)
        return result.scalar() or 0
    
    async def add_to_collection(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        vocabulary_id: uuid.UUID
    ) -> UserVocabulary:
        """
        Add vocabulary to user's collection using UPSERT (atomic, no race condition).
        Returns existing entry if already added.
        """
        now = datetime.now(timezone.utc)
        next_review = now + timedelta(days=1)

        # Try PostgreSQL INSERT … ON CONFLICT DO NOTHING first
        try:
            stmt = (
                pg_insert(UserVocabulary)
                .values(
                    id=uuid.uuid4(),
                    user_id=user_id,
                    vocabulary_id=vocabulary_id,
                    status=VocabularyStatus.LEARNING,
                    ease_factor=2.5,
                    interval=1,
                    repetitions=0,
                    next_review_date=next_review,
                    fsrs_stability=0.0,
                    fsrs_difficulty=0.0,
                    fsrs_elapsed_days=0,
                    fsrs_scheduled_days=0,
                    fsrs_reps=0,
                    fsrs_lapses=0,
                    fsrs_state=0,
                    added_at=now,
                    total_reviews=0,
                    correct_reviews=0,
                    streak=0,
                    longest_streak=0,
                    total_xp_earned=0,
                )
                .on_conflict_do_nothing(index_elements=["user_id", "vocabulary_id"])
                .returning(UserVocabulary.id)
            )
            await db.execute(stmt)
            await db.commit()
        except Exception:
            # Fallback for SQLite / generic engines
            await db.rollback()
            existing = await self.get_user_vocabulary(db, user_id, vocabulary_id)
            if existing:
                return existing
            try:
                user_vocab = UserVocabulary(
                    user_id=user_id,
                    vocabulary_id=vocabulary_id,
                    status=VocabularyStatus.LEARNING,
                    ease_factor=2.5,
                    interval=1,
                    repetitions=0,
                    next_review_date=next_review,
                    fsrs_stability=0.0,
                    fsrs_difficulty=0.0,
                    fsrs_elapsed_days=0,
                    fsrs_scheduled_days=0,
                    fsrs_reps=0,
                    fsrs_lapses=0,
                    fsrs_state=0,
                )
                db.add(user_vocab)
                await db.commit()
                await db.refresh(user_vocab)
                return user_vocab
            except Exception:
                await db.rollback()
                # Race condition: another request inserted the same row
                existing = await self.get_user_vocabulary(db, user_id, vocabulary_id)
                if existing:
                    return existing
                raise

        # Re-fetch so the ORM object is fully loaded
        result = await db.execute(
            select(UserVocabulary).where(
                and_(
                    UserVocabulary.user_id == user_id,
                    UserVocabulary.vocabulary_id == vocabulary_id,
                )
            )
        )
        return result.scalar_one()

    async def bulk_add_to_collection(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        vocabulary_ids: List[uuid.UUID],
    ) -> List[UserVocabulary]:
        """Add existing vocabulary items with one upsert and one commit."""
        unique_ids = list(dict.fromkeys(vocabulary_ids))
        if not unique_ids:
            return []

        valid_ids = list(
            (
                await db.scalars(
                    select(VocabularyItem.id).where(VocabularyItem.id.in_(unique_ids))
                )
            ).all()
        )
        if not valid_ids:
            return []

        now = datetime.now(timezone.utc)
        next_review = now + timedelta(days=1)
        rows = [
            {
                "id": uuid.uuid4(),
                "user_id": user_id,
                "vocabulary_id": vocabulary_id,
                "status": VocabularyStatus.LEARNING,
                "ease_factor": 2.5,
                "interval": 1,
                "repetitions": 0,
                "next_review_date": next_review,
                "fsrs_stability": 0.0,
                "fsrs_difficulty": 0.0,
                "fsrs_elapsed_days": 0,
                "fsrs_scheduled_days": 0,
                "fsrs_reps": 0,
                "fsrs_lapses": 0,
                "fsrs_state": 0,
                "added_at": now,
                "total_reviews": 0,
                "correct_reviews": 0,
                "streak": 0,
                "longest_streak": 0,
                "total_xp_earned": 0,
            }
            for vocabulary_id in valid_ids
        ]
        await db.execute(
            pg_insert(UserVocabulary)
            .values(rows)
            .on_conflict_do_nothing(index_elements=["user_id", "vocabulary_id"])
        )
        result = await db.execute(
            select(UserVocabulary).where(
                UserVocabulary.user_id == user_id,
                UserVocabulary.vocabulary_id.in_(valid_ids),
            )
        )
        by_vocabulary_id = {
            item.vocabulary_id: item for item in result.scalars().all()
        }
        await db.commit()
        return [
            by_vocabulary_id[vocabulary_id]
            for vocabulary_id in vocabulary_ids
            if vocabulary_id in by_vocabulary_id
        ]
    
    async def get_due_vocabulary(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        limit: int = 20
    ) -> List[UserVocabulary]:
        """
        Get vocabulary items due for review.
        Ordered by next_review_date (oldest first).
        """
        query = (
            select(UserVocabulary)
            .join(
                VocabularyItem,
                VocabularyItem.id == UserVocabulary.vocabulary_id,
            )
            .options(joinedload(UserVocabulary.vocabulary))
            .where(
                and_(
                    UserVocabulary.user_id == user_id,
                    UserVocabulary.next_review_date <= datetime.now(timezone.utc),
                    UserVocabulary.status != VocabularyStatus.ARCHIVED,
                ),
                *_valid_definition_conditions(),
            )
            .order_by(UserVocabulary.next_review_date)
            .limit(limit)
        )
        
        result = await db.execute(query)
        return list(result.scalars().all())
    
    async def count_due_vocabulary(
        self,
        db: AsyncSession,
        user_id: uuid.UUID
    ) -> int:
        """Count vocabulary items due for review"""
        result = await db.execute(
            select(func.count())
            .select_from(UserVocabulary)
            .join(
                VocabularyItem,
                VocabularyItem.id == UserVocabulary.vocabulary_id,
            )
            .where(
                and_(
                    UserVocabulary.user_id == user_id,
                    UserVocabulary.next_review_date <= datetime.now(timezone.utc),
                    UserVocabulary.status != VocabularyStatus.ARCHIVED,
                ),
                *_valid_definition_conditions(),
            )
        )
        return result.scalar() or 0
    
    # ===== Review status =====
    #
    # Scheduling itself lives in app/services/learner_state.py (one engine for
    # vocabulary, grammar and missions). The SM-2 and FSRS-lite routines that
    # used to sit here were unreachable from any route once submit_review moved
    # over, so they were removed rather than left as a second source of truth.

    def determine_status_from_mastery(
        self,
        mastery_probability: float,
        attempt_count: int,
        stability_days: float,
    ) -> VocabularyStatus:
        """
        Determine vocabulary status from learner_concept_state fields.

        Mastered: mastery_probability >= 0.85 AND stability_days >= 21.
        Both halves are needed to match the old ease_factor>=2.5 +
        interval>=21 bar: mastery alone crosses 0.85 after three same-day
        correct answers, which marked a word mastered for cramming it rather
        than for remembering it.
        Reviewing: attempt_count >= 3 (equivalent to the old repetitions>=3)
        Learning: otherwise
        """
        if mastery_probability >= MASTERED_MASTERY and stability_days >= MASTERED_STABILITY_DAYS:
            return VocabularyStatus.MASTERED
        elif attempt_count >= 3:
            return VocabularyStatus.REVIEWING
        else:
            return VocabularyStatus.LEARNING

    async def submit_review(
        self,
        db: AsyncSession,
        user_vocabulary_id: uuid.UUID,
        quality: int,
        time_spent_ms: int = 0
    ) -> UserVocabulary:
        """
        Submit a vocabulary review.

        Scheduling (next_review_date) and mastery status are driven by the
        unified learner_concept_state engine (app/services/learner_state.py)
        — the same BKT+FSRS algorithm used for grammar/mission concepts —
        applied synchronously in this same transaction (bypassing the async
        outbox worker) so the response still reflects the update
        immediately. Legacy SM-2/FSRS columns on UserVocabulary are frozen
        (no longer written here); they remain as historical data.
        """
        # Get user vocabulary (eager-load word for concept_id derivation)
        result = await db.execute(
            select(UserVocabulary)
            .options(joinedload(UserVocabulary.vocabulary))
            .where(UserVocabulary.id == user_vocabulary_id)
        )
        user_vocab = result.scalar_one()

        now = datetime.now(timezone.utc)
        concept_id = _vocab_concept_id(user_vocab.vocabulary.word)
        outcome, confidence = grade_to_observation(quality)
        event_id = hashlib.sha256(
            f"{user_vocabulary_id}:{quality}:{now.isoformat()}".encode("utf-8")
        ).hexdigest()

        await ingest_observations(
            db,
            [
                ObservationInput(
                    event_id=event_id,
                    user_id=user_vocab.user_id,
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
                LearnerConceptState.user_id == user_vocab.user_id,
                LearnerConceptState.concept_id == concept_id,
            )
        )

        # Sync UserVocabulary as a read-cache so GET /vocabulary/due (which
        # queries UserVocabulary.next_review_date) reflects the unified
        # engine without needing its own query rewrite.
        user_vocab.next_review_date = concept_state.next_review_at
        user_vocab.last_reviewed_at = now
        user_vocab.total_reviews += 1

        # Update streak and stats
        if quality >= 3:  # Correct answer
            user_vocab.correct_reviews += 1
            user_vocab.streak += 1
            if user_vocab.streak > user_vocab.longest_streak:
                user_vocab.longest_streak = user_vocab.streak
        else:  # Incorrect answer
            user_vocab.streak = 0

        # Update status
        user_vocab.status = self.determine_status_from_mastery(
            concept_state.mastery_probability,
            concept_state.attempt_count,
            concept_state.stability_days,
        )

        # Award XP (base: 5, bonus for quality and streak)
        xp_award = 5 + (quality * 2) + min(user_vocab.streak // 5, 10)
        user_vocab.total_xp_earned += xp_award

        # Create review record (ease/interval frozen at their last historical
        # value — no longer recomputed here, kept only for audit continuity)
        review = VocabularyReview(
            user_vocabulary_id=user_vocabulary_id,
            quality=quality,
            time_spent_ms=time_spent_ms,
            ease_factor_after=user_vocab.ease_factor,
            interval_after=user_vocab.interval
        )

        db.add(review)
        await db.commit()
        await db.refresh(user_vocab)

        return user_vocab
    
    # ===== Statistics =====
    
    async def get_user_vocabulary_stats(
        self,
        db: AsyncSession,
        user_id: uuid.UUID
    ) -> dict:
        """Get user's vocabulary statistics"""
        # Count by status
        result = await db.execute(
            select(
                UserVocabulary.status,
                func.count(UserVocabulary.id)
            ).where(
                UserVocabulary.user_id == user_id
            ).group_by(UserVocabulary.status)
        )
        
        status_counts = {row[0]: row[1] for row in result.all()}
        
        # Count due for review
        due_count = await self.count_due_vocabulary(db, user_id)
        
        # Total XP earned
        result = await db.execute(
            select(func.sum(UserVocabulary.total_xp_earned)).where(
                UserVocabulary.user_id == user_id
            )
        )
        total_xp = result.scalar() or 0
        
        # Best streak
        result = await db.execute(
            select(func.max(UserVocabulary.longest_streak)).where(
                UserVocabulary.user_id == user_id
            )
        )
        best_streak = result.scalar() or 0
        
        return {
            "total": sum(status_counts.values()),
            "learning": status_counts.get(VocabularyStatus.LEARNING, 0),
            "reviewing": status_counts.get(VocabularyStatus.REVIEWING, 0),
            "mastered": status_counts.get(VocabularyStatus.MASTERED, 0),
            "due_for_review": due_count,
            "total_xp": total_xp,
            "best_streak": best_streak
        }
    
    # ===== Vocabulary Decks =====
    
    async def create_deck(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        name: str,
        description: Optional[str] = None,
        color: str = "#2196F3"
    ) -> VocabularyDeck:
        """Create a new vocabulary deck"""
        deck = VocabularyDeck(
            user_id=user_id,
            name=name,
            description=description,
            color=color
        )
        
        db.add(deck)
        await db.commit()
        await db.refresh(deck)
        
        return deck
    
    async def get_user_decks(
        self,
        db: AsyncSession,
        user_id: uuid.UUID
    ) -> List[VocabularyDeck]:
        """Get all decks for a user with computed item counts"""
        query = (
            select(VocabularyDeck, func.count(VocabularyDeckItem.id).label("item_count"))
            .outerjoin(VocabularyDeckItem, VocabularyDeckItem.deck_id == VocabularyDeck.id)
            .where(VocabularyDeck.user_id == user_id)
            .group_by(VocabularyDeck.id)
            .order_by(VocabularyDeck.created_at.desc())
        )
        result = await db.execute(query)
        decks = []
        for row in result.all():
            deck, count = row
            deck.item_count = count  # Assign count to the dynamic item_count field
            decks.append(deck)
        return decks

    async def get_deck(
        self,
        db: AsyncSession,
        deck_id: uuid.UUID
    ) -> Optional[VocabularyDeck]:
        """Get deck by ID"""
        result = await db.execute(
            select(VocabularyDeck).where(VocabularyDeck.id == deck_id)
        )
        return result.scalar_one_or_none()

    async def delete_deck(
        self,
        db: AsyncSession,
        deck_id: uuid.UUID
    ) -> bool:
        """Delete a deck"""
        deck = await self.get_deck(db, deck_id)
        if not deck:
            return False
        await db.delete(deck)
        await db.commit()
        return True

    async def get_deck_items(
        self,
        db: AsyncSession,
        deck_id: uuid.UUID
    ) -> List[UserVocabulary]:
        """Get all user vocabulary items in a deck with vocabulary relationships loaded"""
        query = (
            select(UserVocabulary)
            .join(VocabularyDeckItem, VocabularyDeckItem.user_vocabulary_id == UserVocabulary.id)
            .join(
                VocabularyItem,
                VocabularyItem.id == UserVocabulary.vocabulary_id,
            )
            .options(joinedload(UserVocabulary.vocabulary))
            .where(
                VocabularyDeckItem.deck_id == deck_id,
                *_valid_definition_conditions(),
            )
            .order_by(VocabularyDeckItem.order, VocabularyDeckItem.added_at.desc())
        )
        result = await db.execute(query)
        return list(result.scalars().all())
    
    async def add_to_deck(
        self,
        db: AsyncSession,
        deck_id: uuid.UUID,
        user_vocabulary_id: uuid.UUID,
        order: int = 0
    ) -> VocabularyDeckItem:
        """Add vocabulary to a deck (idempotent)"""
        # Check if already in deck
        result = await db.execute(
            select(VocabularyDeckItem).where(
                and_(
                    VocabularyDeckItem.deck_id == deck_id,
                    VocabularyDeckItem.user_vocabulary_id == user_vocabulary_id
                )
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            return existing
        
        # Add to deck
        deck_item = VocabularyDeckItem(
            deck_id=deck_id,
            user_vocabulary_id=user_vocabulary_id,
            order=order
        )
        
        db.add(deck_item)
        await db.commit()
        await db.refresh(deck_item)
        
        return deck_item

    async def remove_from_deck(
        self,
        db: AsyncSession,
        deck_id: uuid.UUID,
        user_vocabulary_id: uuid.UUID
    ) -> bool:
        """Remove a vocabulary item from a deck"""
        result = await db.execute(
            select(VocabularyDeckItem).where(
                and_(
                    VocabularyDeckItem.deck_id == deck_id,
                    VocabularyDeckItem.user_vocabulary_id == user_vocabulary_id
                )
            )
        )
        deck_item = result.scalar_one_or_none()
        if not deck_item:
            return False
        await db.delete(deck_item)
        await db.commit()
        return True

    async def ensure_basic_words_for_user(
        self,
        db: AsyncSession,
        user: "User | uuid.UUID"
    ) -> None:
        """
        Check if user has all 'basic_200' words in their collection.
        If any are missing, bulk add them.
        """
        from app.models.user import User
        
        # 1. Resolve User object and check has_seeded_basic_words flag
        if isinstance(user, uuid.UUID):
            user_obj = await db.get(User, user)
            if not user_obj:
                return
        else:
            user_obj = user
            
        if user_obj.has_seeded_basic_words:
            return

        user_id = user_obj.id
        from sqlalchemy import insert
        
        # 2. Fetch all 'basic_200' vocabulary item IDs
        basic_items_query = select(VocabularyItem)
        basic_items_result = await db.execute(basic_items_query)
        basic_items = [
            item
            for item in basic_items_result.scalars().all()
            if has_tag(item.tags, "basic_200")
        ]
        
        if not basic_items:
            # The source catalog may be populated later during deployment.
            # Leave the flag unset so a later request can retry seeding.
            return

        try:
            assignments = select_balanced_starter_vocabulary(
                VocabularyCandidate(
                    id=item.id,
                    word=item.word,
                    definition=item.definition,
                    usage_frequency=item.usage_frequency,
                    tags=item.tags,
                    created_at=item.created_at,
                )
                for item in basic_items
            )
        except ValueError:
            # Migration or catalog import has not produced a complete balanced
            # starter set yet. Do not mark the user as seeded with partial data.
            return

        basic_item_ids = [assignment.candidate.id for assignment in assignments]
            
        # 3. Fetch vocabulary item IDs already in user's collection
        user_vocab_query = select(UserVocabulary.vocabulary_id).where(
            UserVocabulary.user_id == user_id
        )
        user_vocab_result = await db.execute(user_vocab_query)
        existing_vocab_ids = {r[0] for r in user_vocab_result.all()}
        
        # 4. Find missing basic word IDs
        missing_ids = [vid for vid in basic_item_ids if vid not in existing_vocab_ids]
        
        if missing_ids:
            # 5. Bulk insert missing words using SQLAlchemy core insert statement
            now = datetime.now(timezone.utc)
            next_review = now + timedelta(days=1)
            
            bulk_data = [
                {
                    "id": uuid.uuid4(),
                    "user_id": user_id,
                    "vocabulary_id": vid,
                    "status": VocabularyStatus.LEARNING,
                    "ease_factor": 2.5,
                    "interval": 1,
                    "repetitions": 0,
                    "next_review_date": next_review,
                    "fsrs_stability": 0.0,
                    "fsrs_difficulty": 0.0,
                    "fsrs_elapsed_days": 0,
                    "fsrs_scheduled_days": 0,
                    "fsrs_reps": 0,
                    "fsrs_lapses": 0,
                    "fsrs_state": 0,
                    "added_at": now,
                    "total_reviews": 0,
                    "correct_reviews": 0,
                    "streak": 0,
                    "longest_streak": 0,
                    "total_xp_earned": 0,
                }
                for vid in missing_ids
            ]
            await db.execute(insert(UserVocabulary), bulk_data)

        # 6. Mark user as seeded and commit
        user_obj.has_seeded_basic_words = True
        db.add(user_obj)
        await db.commit()


# Global instance
vocabulary_crud = VocabularyCRUD()
