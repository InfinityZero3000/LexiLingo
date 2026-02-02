"""
SQLAlchemy Models

Import all models here for Alembic auto-detection
Extended with Phase 1-4 models
"""

# User models (Phase 1)
from app.models.user import User, UserDevice, RefreshToken

# Course models (Phase 2)
from app.models.course import Course, Unit, Lesson, MediaResource
from app.models.course_category import CourseCategory

# Vocabulary models (Phase 3)
from app.models.vocabulary import (
    VocabularyItem,
    UserVocabulary,
    VocabularyReview,
    VocabularyDeck,
    VocabularyDeckItem
)

# Progress & Learning models (Phase 3)
from app.models.progress import (
    UserProgress,
    LessonAttempt,
    QuestionAttempt,
    UserVocabKnowledge,
    DailyReviewSession,
    Streak,
)

# Gamification models (Phase 4)
from app.models.gamification import (
    Achievement,
    UserAchievement,
    UserWallet,
    WalletTransaction,
    LeaderboardEntry,
    UserFollowing,
    ActivityFeed,
    ShopItem,
    UserInventory,
)

# Proficiency Assessment models
from app.models.proficiency import (
    SkillType,
    UserProficiencyProfile,
    UserSkillScore,
    UserLevelHistory,
    ExerciseAttempt,
    LevelAssessmentTest,
)

__all__ = [
    # User (Phase 1)
    "User",
    "UserDevice",
    "RefreshToken",
    # Course (Phase 2)
    "Course",
    "CourseCategory",
    "Unit",
    "Lesson",
    "MediaResource",
    # Vocabulary (Phase 3)
    "VocabularyItem",
    "UserVocabulary",
    "VocabularyReview",
    "VocabularyDeck",
    "VocabularyDeckItem",
    # Progress (Phase 3)
    "UserProgress",
    "LessonAttempt",
    "QuestionAttempt",
    "UserVocabKnowledge",
    "DailyReviewSession",
    "Streak",
    # Gamification (Phase 4)
    "Achievement",
    "UserAchievement",
    "UserWallet",
    "WalletTransaction",
    "LeaderboardEntry",
    "UserFollowing",
    "ActivityFeed",
    "ShopItem",
    "UserInventory",
    # Proficiency Assessment
    "SkillType",
    "UserProficiencyProfile",
    "UserSkillScore",
    "UserLevelHistory",
    "ExerciseAttempt",
    "LevelAssessmentTest",
]
