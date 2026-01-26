"""
Vocabulary CRUD Operations
Phase 3: Spaced Repetition System with SuperMemo SM-2 Algorithm
"""

import uuid
from datetime import datetime, timedelta
from typing import Optional, List
from sqlalchemy import select, func, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.vocabulary import (
    VocabularyItem,
    UserVocabulary,
    VocabularyReview,
    VocabularyDeck,
    VocabularyDeckItem,
    VocabularyStatus
)


class VocabularyCRUD:
    """CRUD operations for vocabulary management"""
    
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
        """Get user's vocabulary collection"""
        query = select(UserVocabulary).where(UserVocabulary.user_id == user_id)
        
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
        Add vocabulary to user's collection.
        Idempotent: Returns existing entry if already added.
        """
        # Check if already exists
        existing = await self.get_user_vocabulary(db, user_id, vocabulary_id)
        if existing:
            return existing
        
        # Create new entry
        user_vocab = UserVocabulary(
            user_id=user_id,
            vocabulary_id=vocabulary_id,
            status=VocabularyStatus.LEARNING,
            ease_factor=2.5,
            interval=1,
            repetitions=0,
            next_review_date=datetime.utcnow() + timedelta(days=1)
        )
        
        db.add(user_vocab)
        await db.commit()
        await db.refresh(user_vocab)
        
        return user_vocab
    
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
                UserVocabulary.next_review_date <= datetime.utcnow(),
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
                    UserVocabulary.next_review_date <= datetime.utcnow(),
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
        next_review_date = datetime.utcnow() + timedelta(days=interval)
        
        return ease_factor, interval, repetitions, next_review_date
    
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
        
        # Calculate new SRS parameters
        new_ease, new_interval, new_reps, next_review = self.calculate_next_review(
            quality=quality,
            ease_factor=user_vocab.ease_factor,
            interval=user_vocab.interval,
            repetitions=user_vocab.repetitions
        )
        
        # Update user vocabulary
        user_vocab.ease_factor = new_ease
        user_vocab.interval = new_interval
        user_vocab.repetitions = new_reps
        user_vocab.next_review_date = next_review
        user_vocab.last_reviewed_at = datetime.utcnow()
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
        """Get all decks for a user"""
        result = await db.execute(
            select(VocabularyDeck).where(
                VocabularyDeck.user_id == user_id
            ).order_by(VocabularyDeck.created_at.desc())
        )
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


# Global instance
vocabulary_crud = VocabularyCRUD()
