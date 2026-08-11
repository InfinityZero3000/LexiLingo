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
from app.models.user_grammar_item import UserGrammarItem

# RBAC models
from app.models.rbac import (
    Role,
    Permission,
    RolePermission,
    AuditLog,
)

# Notification model
from app.models.notification import Notification
from app.models.reward_grant import UserRewardGrant

# Reminder models
from app.models.reminder import ReminderDelivery, UserReminderPreference

# Mistake notebook models
from app.models.mistake import MistakeNotebookEntry

# API Cache (Phase 0 — Infrastructure)
from app.models.api_cache import APICacheEntry

# Games models (Phase 3)
from app.models.games import (
    GameWord,
    GameSession,
    XPTransaction,
)

# CEFR content-agent models
from app.models.content_agent import (
    ContentAgentJob,
    ContentAgentUpload,
    ContentProvenance,
    LessonVocabularyItem,
)

# Ranking/Gamification Agent models
from app.models.ranking_agent import RankingAgentJob

# Notification Campaign Agent models
from app.models.notification_campaign import NotificationCampaignJob

# Durable learner error history
from app.models.learner_error import LearnerError

# Sparse learner-state and durable observation outbox
from app.models.learner_state import (
    LearnerConceptState,
    LearnerObservationEvent,
    LearnerStateProfile,
)

from app.models.partner import PartnerApiKey

# Entitlement models (server-verified premium state)
from app.models.entitlement import UserEntitlement

__all__ = [
    "PartnerApiKey",
    # User (Phase 1)
    "User",
    "UserDevice",
    "RefreshToken",
    "UserRewardGrant",
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
    "UserGrammarItem",
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
    # Mistake notebook
    "MistakeNotebookEntry",
    # API Cache (Phase 0)
    "APICacheEntry",
    # Games (Phase 3)
    "GameWord",
    "GameSession",
    "XPTransaction",
    # CEFR content agent
    "ContentAgentJob",
    "ContentAgentUpload",
    "ContentProvenance",
    "LessonVocabularyItem",
    # Ranking/Gamification Agent
    "RankingAgentJob",
    # Notification Campaign Agent
    "NotificationCampaignJob",
    # Learner error history
    "LearnerError",
    # Learner state
    "LearnerConceptState",
    "LearnerObservationEvent",
    "LearnerStateProfile",
    # Entitlements
    "UserEntitlement",
]
