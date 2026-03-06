"""
Games Models — English Games + XP System
Phase 3: English Games with XP accumulation

Models:
- GameWord: Word library per CEFR level for games
- GameSession: Track each game played
- XPTransaction: Audit trail for all XP awards
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, Text, JSON, Float, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID


class GameWord(Base):
    """
    Word library for games (Word Scramble, Hangman, Spelling Bee, Matching).
    Pre-seeded per CEFR level and category.
    """

    __tablename__ = "game_words"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(), primary_key=True, default=uuid.uuid4
    )

    word: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    definition: Mapped[str] = mapped_column(Text, nullable=False)
    hint: Mapped[str] = mapped_column(Text, nullable=True)  # Brief hint without giving away
    example_sentence: Mapped[str] = mapped_column(Text, nullable=True)
    ipa_pronunciation: Mapped[str] = mapped_column(String(200), nullable=True)

    cefr_level: Mapped[str] = mapped_column(String(2), nullable=False, index=True)  # A1–C2
    category: Mapped[str] = mapped_column(String(50), nullable=False, index=True)   # food, animals, etc.

    # Synonyms/Vietnamese for matching game variations
    synonyms: Mapped[list] = mapped_column(JSON, nullable=True)         # ["large", "vast"]
    vietnamese_translation: Mapped[str] = mapped_column(String(200), nullable=True)

    # Word difficulty metadata
    letter_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    xp_value: Mapped[int] = mapped_column(Integer, default=10)  # Base XP for this word

    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("idx_game_words_level_category", "cefr_level", "category"),
    )

    def __repr__(self) -> str:
        return f"<GameWord {self.word} [{self.cefr_level}]>"


class GameSession(Base):
    """
    Record of each game played by a user.
    Used for anti-cheat validation, leaderboards, and progress tracking.
    """

    __tablename__ = "game_sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(), primary_key=True, default=uuid.uuid4
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    game_type: Mapped[str] = mapped_column(
        String(50), nullable=False, index=True
    )  # word_scramble | fill_blank | matching | spelling_bee | grammar_quiz | hangman

    # Score details
    score: Mapped[int] = mapped_column(Integer, default=0)            # Raw score (e.g. correct answers)
    total_questions: Mapped[int] = mapped_column(Integer, default=0)  # Total possible
    correct_answers: Mapped[int] = mapped_column(Integer, default=0)
    xp_earned: Mapped[int] = mapped_column(Integer, default=0)

    # Session metadata
    cefr_level: Mapped[str] = mapped_column(String(2), nullable=True)  # Level played at
    category: Mapped[str] = mapped_column(String(50), nullable=True)   # Category chosen
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=True)  # Actual play time

    # Anti-cheat fields
    started_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    completed_at: Mapped[datetime] = mapped_column(DateTime, nullable=True)
    xp_awarded: Mapped[bool] = mapped_column(Boolean, default=False)

    # Extra data (hints used, streak at time of game, etc.)
    session_data: Mapped[dict] = mapped_column(JSON, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("idx_game_sessions_user_type", "user_id", "game_type"),
        Index("idx_game_sessions_created", "created_at"),
    )

    def __repr__(self) -> str:
        return f"<GameSession {self.game_type} user={self.user_id} xp={self.xp_earned}>"


class XPTransaction(Base):
    """
    Immutable audit log of all XP awards across all sources.
    Used for leaderboards, history view, and anti-cheat.
    """

    __tablename__ = "xp_transactions"

    id: Mapped[uuid.UUID] = mapped_column(
        GUID(), primary_key=True, default=uuid.uuid4
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    amount: Mapped[int] = mapped_column(Integer, nullable=False)  # XP awarded (after multipliers)
    base_amount: Mapped[int] = mapped_column(Integer, nullable=False)  # Raw XP before multipliers
    multiplier: Mapped[float] = mapped_column(Float, default=1.0)     # Streak multiplier applied

    # Source tracking
    source: Mapped[str] = mapped_column(
        String(50), nullable=False, index=True
    )  # game | news | youtube | podcast | book | lesson | daily_challenge
    source_id: Mapped[str] = mapped_column(String(100), nullable=True)  # e.g. game session UUID
    source_detail: Mapped[str] = mapped_column(String(100), nullable=True)  # e.g. "word_scramble"

    # Level snapshot at time of award
    level_before: Mapped[int] = mapped_column(Integer, nullable=True)
    level_after: Mapped[int] = mapped_column(Integer, nullable=True)
    leveled_up: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)

    __table_args__ = (
        Index("idx_xp_transactions_user_created", "user_id", "created_at"),
        Index("idx_xp_transactions_source", "source"),
    )

    def __repr__(self) -> str:
        return f"<XPTransaction {self.source} +{self.amount} user={self.user_id}>"
