"""
SQLAlchemy Models

Import all models here for Alembic auto-detection
Extended with Phase 1-4 models + RBAC
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
    UserCourseProgress,
    LessonCompletion,
    LessonAttempt,
    QuestionAttempt,
    UserVocabKnowledge,
    DailyReviewSession,
    Streak,
    DailyActivity,
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
    ChallengeRewardClaim,
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

# Content lab models (Grammar, Questions, Test Exams)
from app.models.content import (
    GrammarItem,
    QuestionItem,
    TestExam,
)

# RBAC models
from app.models.rbac import (
    Role,
    Permission,
    RolePermission,
    AuditLog,
)

# Notification model
from app.models.notification import Notification

# Reminder models
from app.models.reminder import ReminderDelivery, UserReminderPreference

# API Cache (Phase 0 — Infrastructure)
from app.models.api_cache import APICacheEntry

# Games models (Phase 3)
from app.models.games import (
    GameWord,
    GameSession,
    XPTransaction,
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
    "UserCourseProgress",
    "LessonCompletion",
    "LessonAttempt",
    "QuestionAttempt",
    "UserVocabKnowledge",
    "DailyReviewSession",
    "Streak",
    "DailyActivity",
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
    "ChallengeRewardClaim",
    # Proficiency Assessment
    "SkillType",
    "UserProficiencyProfile",
    "UserSkillScore",
    "UserLevelHistory",
    "ExerciseAttempt",
    "LevelAssessmentTest",
    # Content lab
    "GrammarItem",
    "QuestionItem",
    "TestExam",
    # RBAC
    "Role",
    "Permission",
    "RolePermission",
    "AuditLog",
    # Notification
    "Notification",
    # Reminder
    "ReminderDelivery",
    "UserReminderPreference",
    # API Cache (Phase 0)
    "APICacheEntry",
    # Games (Phase 3)
    "GameWord",
    "GameSession",
    "XPTransaction",
]
