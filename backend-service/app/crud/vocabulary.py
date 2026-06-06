"""
Vocabulary CRUD Operations
Phase 3: Spaced Repetition System with SuperMemo SM-2 Algorithm
"""

import uuid
import re
import math
from datetime import datetime, timedelta, timezone
from typing import Optional, List, TYPE_CHECKING
from sqlalchemy import select, func, and_, or_
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import joinedload
from sqlalchemy.ext.asyncio import AsyncSession

if TYPE_CHECKING:
    from app.models.user import User


from app.models.vocabulary import (
    VocabularyItem,
    UserVocabulary,
    VocabularyReview,
    VocabularyDeck,
    VocabularyDeckItem,
    VocabularyStatus,
    PartOfSpeech,
    DifficultyLevel,
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
            conditions.append(VocabularyItem.course_id == course_id)
        if lesson_id:
            conditions.append(VocabularyItem.lesson_id == lesson_id)
        if difficulty_level:
            conditions.append(VocabularyItem.difficulty_level == difficulty_level)
        if tag:
            if db.bind.dialect.name == "postgresql":
                from sqlalchemy.dialects.postgresql import JSONB
                from sqlalchemy import cast
                conditions.append(cast(VocabularyItem.tags, JSONB).contains([tag]))
            else:
                conditions.append(VocabularyItem.tags.contains([tag]))
        
        if conditions:
            query = query.where(and_(*conditions))
        
        query = query.limit(limit).offset(offset).order_by(VocabularyItem.word)
        
        result = await db.execute(query)
        return list(result.scalars().all())
    
    async def search_vocabulary(
        self,
        db: AsyncSession,
        search_term: str,
        limit: int = 20
    ) -> List[VocabularyItem]:
        """Search vocabulary by word (case-insensitive)"""
        query = select(VocabularyItem).where(
            VocabularyItem.word.ilike(f"%{search_term}%")
        ).limit(limit).order_by(VocabularyItem.word)
        
        result = await db.execute(query)
        return list(result.scalars().all())

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
            .where(UserVocabulary.user_id == user_id)
        )

        if status:
            query = query.where(UserVocabulary.status == status)

        query = query.limit(limit).offset(offset).order_by(UserVocabulary.added_at.desc())

        result = await db.execute(query)
        return list(result.scalars().all())
    
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
        query = select(UserVocabulary).where(
            and_(
                UserVocabulary.user_id == user_id,
                UserVocabulary.next_review_date <= datetime.now(timezone.utc),
                UserVocabulary.status != VocabularyStatus.ARCHIVED
            )
        ).order_by(UserVocabulary.next_review_date).limit(limit)
        
        result = await db.execute(query)
        return list(result.scalars().all())
    
    async def count_due_vocabulary(
        self,
        db: AsyncSession,
        user_id: uuid.UUID
    ) -> int:
        """Count vocabulary items due for review"""
        result = await db.execute(
            select(func.count()).select_from(UserVocabulary).where(
                and_(
                    UserVocabulary.user_id == user_id,
                    UserVocabulary.next_review_date <= datetime.now(timezone.utc),
                    UserVocabulary.status != VocabularyStatus.ARCHIVED
                )
            )
        )
        return result.scalar() or 0
    
    # ===== SRS Algorithm (SuperMemo SM-2) =====
    
    def calculate_next_review(
        self,
        quality: int,
        ease_factor: float,
        interval: int,
        repetitions: int
    ) -> tuple[float, int, int, datetime]:
        """
        Calculate next review parameters using SM-2 algorithm.
        
        Args:
            quality: 0-5 rating (0=blackout, 5=perfect)
            ease_factor: Current ease factor (1.3-3.0)
            interval: Current interval in days
            repetitions: Number of consecutive correct answers
        
        Returns:
            (new_ease_factor, new_interval, new_repetitions, next_review_date)
        """
        # Quality < 3: Failed review, reset
        if quality < 3:
            repetitions = 0
            interval = 1
        else:
            # Successful review
            if repetitions == 0:
                interval = 1
            elif repetitions == 1:
                interval = 6
            else:
                interval = int(interval * ease_factor)
            
            repetitions += 1
        
        # Update ease factor based on quality
        ease_factor = ease_factor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
        ease_factor = max(1.3, ease_factor)  # Minimum ease factor
        
        # Calculate next review date
        next_review_date = datetime.now(timezone.utc) + timedelta(days=interval)
        
        return ease_factor, interval, repetitions, next_review_date

    def _clamp(self, value: float, lower: float, upper: float) -> float:
        """Clamp a numeric value to an inclusive range."""
        return max(lower, min(upper, value))

    def calculate_fsrs_review(
        self,
        quality: int,
        stability: Optional[float],
        difficulty: Optional[float],
        scheduled_days: Optional[int],
        reps: Optional[int],
        lapses: Optional[int],
        fsrs_last_review: Optional[datetime],
        sm2_last_review: Optional[datetime],
        now: Optional[datetime] = None,
    ) -> dict:
        """
        Calculate FSRS-style scheduling fields for a review.

        This intentionally keeps FSRS side-by-side with the existing SM-2 fields.
        It uses the FSRS concepts of stability, difficulty, retrievability, reps,
        lapses, state, elapsed days, and scheduled days without adding a new
        dependency or changing existing review contracts.
        """
        now = now or datetime.now(timezone.utc)
        quality = max(0, min(5, quality))

        last_review = fsrs_last_review or sm2_last_review
        if last_review and last_review.tzinfo is None:
            last_review = last_review.replace(tzinfo=timezone.utc)
        elapsed_days = max(0, (now - last_review).days) if last_review else 0

        current_reps = max(0, reps or 0)
        current_lapses = max(0, lapses or 0)
        current_scheduled_days = max(0, scheduled_days or 0)
        current_stability = stability if stability and stability > 0 else None
        current_difficulty = difficulty if difficulty and difficulty > 0 else None

        if current_reps == 0 or current_stability is None or current_difficulty is None:
            initial_stability = {
                0: 0.4,
                1: 0.6,
                2: 1.0,
                3: 2.4,
                4: 3.8,
                5: 5.8,
            }[quality]
            new_stability = initial_stability
            new_difficulty = self._clamp(7.0 - (quality - 3) * 0.8, 1.0, 10.0)
        else:
            decay = -0.5
            factor = 19 / 81
            retrievability = (1 + factor * elapsed_days / current_stability) ** decay
            retrievability = self._clamp(retrievability, 0.01, 1.0)

            mean_reversion = (4.0 - current_difficulty) * 0.05
            new_difficulty = self._clamp(
                current_difficulty - (quality - 3) * 0.3 + mean_reversion,
                1.0,
                10.0,
            )

            if quality < 3:
                new_stability = max(0.5, current_stability * 0.55)
            else:
                rating_boost = {3: 1.2, 4: 2.0, 5: 2.8}[quality]
                difficulty_factor = (11.0 - new_difficulty) / 10.0
                recall_gap = 1.0 - retrievability
                growth = 1.0 + rating_boost * difficulty_factor * (recall_gap + 0.2)
                new_stability = max(current_stability + 0.5, current_stability * growth)

        if quality < 3:
            next_lapses = current_lapses + 1
            next_state = 3 if current_reps > 0 else 1  # relearning or learning
            next_scheduled_days = 1
        else:
            next_lapses = current_lapses
            next_state = 2 if new_stability >= 2 else 1  # review or learning
            next_scheduled_days = max(1, int(math.ceil(new_stability)))
            if quality == 3 and current_scheduled_days:
                next_scheduled_days = min(next_scheduled_days, current_scheduled_days + 1)
            elif quality == 5:
                next_scheduled_days = max(next_scheduled_days, int(math.ceil(new_stability * 1.15)))

        next_scheduled_days = min(next_scheduled_days, 36500)

        return {
            "fsrs_stability": round(new_stability, 4),
            "fsrs_difficulty": round(new_difficulty, 4),
            "fsrs_elapsed_days": elapsed_days,
            "fsrs_scheduled_days": next_scheduled_days,
            "fsrs_reps": current_reps + 1,
            "fsrs_lapses": next_lapses,
            "fsrs_state": next_state,
            "fsrs_last_review": now,
            "next_review_date": now + timedelta(days=next_scheduled_days),
        }
    
    def determine_status(self, ease_factor: float, interval: int, repetitions: int) -> VocabularyStatus:
        """
        Determine vocabulary status based on SRS parameters.
        
        Mastered: ease_factor >= 2.5 AND interval >= 21 days
        Reviewing: repetitions >= 3
        Learning: Otherwise
        """
        if ease_factor >= 2.5 and interval >= 21:
            return VocabularyStatus.MASTERED
        elif repetitions >= 3:
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
        Submit a vocabulary review and update SRS parameters.
        Awards XP based on quality and streak.
        """
        # Get user vocabulary
        result = await db.execute(
            select(UserVocabulary).where(UserVocabulary.id == user_vocabulary_id)
        )
        user_vocab = result.scalar_one()
        
        now = datetime.now(timezone.utc)

        # Calculate new SRS parameters
        new_ease, new_interval, new_reps, next_review = self.calculate_next_review(
            quality=quality,
            ease_factor=user_vocab.ease_factor,
            interval=user_vocab.interval,
            repetitions=user_vocab.repetitions
        )

        fsrs_update = self.calculate_fsrs_review(
            quality=quality,
            stability=user_vocab.fsrs_stability,
            difficulty=user_vocab.fsrs_difficulty,
            scheduled_days=user_vocab.fsrs_scheduled_days,
            reps=user_vocab.fsrs_reps,
            lapses=user_vocab.fsrs_lapses,
            fsrs_last_review=user_vocab.fsrs_last_review,
            sm2_last_review=user_vocab.last_reviewed_at,
            now=now,
        )
        
        # Update user vocabulary
        user_vocab.ease_factor = new_ease
        user_vocab.interval = new_interval
        user_vocab.repetitions = new_reps
        user_vocab.next_review_date = fsrs_update["next_review_date"] or next_review
        user_vocab.last_reviewed_at = now
        user_vocab.fsrs_stability = fsrs_update["fsrs_stability"]
        user_vocab.fsrs_difficulty = fsrs_update["fsrs_difficulty"]
        user_vocab.fsrs_elapsed_days = fsrs_update["fsrs_elapsed_days"]
        user_vocab.fsrs_scheduled_days = fsrs_update["fsrs_scheduled_days"]
        user_vocab.fsrs_reps = fsrs_update["fsrs_reps"]
        user_vocab.fsrs_lapses = fsrs_update["fsrs_lapses"]
        user_vocab.fsrs_state = fsrs_update["fsrs_state"]
        user_vocab.fsrs_last_review = fsrs_update["fsrs_last_review"]
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
        user_vocab.status = self.determine_status(new_ease, new_interval, new_reps)
        
        # Award XP (base: 5, bonus for quality and streak)
        xp_award = 5 + (quality * 2) + min(user_vocab.streak // 5, 10)
        user_vocab.total_xp_earned += xp_award
        
        # Create review record
        review = VocabularyReview(
            user_vocabulary_id=user_vocabulary_id,
            quality=quality,
            time_spent_ms=time_spent_ms,
            ease_factor_after=new_ease,
            interval_after=new_interval
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
            .options(joinedload(UserVocabulary.vocabulary))
            .where(VocabularyDeckItem.deck_id == deck_id)
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
        from sqlalchemy.dialects.postgresql import JSONB
        from sqlalchemy import cast, insert
        
        # 2. Fetch all 'basic_200' vocabulary item IDs
        if db.bind.dialect.name == "postgresql":
            basic_items_query = select(VocabularyItem.id).where(
                cast(VocabularyItem.tags, JSONB).contains(["basic_200"])
            )
        else:
            basic_items_query = select(VocabularyItem.id).where(
                VocabularyItem.tags.contains(["basic_200"])
            )
            
        basic_items_result = await db.execute(basic_items_query)
        basic_item_ids = [r[0] for r in basic_items_result.all()]
        
        if not basic_item_ids:
            # Mark as seeded even if empty, to avoid querying again
            user_obj.has_seeded_basic_words = True
            db.add(user_obj)
            await db.commit()
            return
            
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
