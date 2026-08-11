"""
User Deletion Service

Shared GDPR-style hard delete used by both the user's own account
deletion and the admin permanent-delete action.
"""
from sqlalchemy import delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User, UserDevice, RefreshToken
from app.models.progress import (
    UserProgress, LessonAttempt, Streak, UserCourseProgress, LessonCompletion,
    QuestionAttempt, UserVocabKnowledge, DailyReviewSession, DailyActivity,
)
from app.models.gamification import (
    UserAchievement, UserWallet, WalletTransaction, LeaderboardEntry,
    UserFollowing, ActivityFeed, UserInventory, ChallengeRewardClaim,
)
from app.models.vocabulary import UserVocabulary, VocabularyReview, VocabularyDeck
from app.models.notification import Notification
from app.models.proficiency import (
    UserProficiencyProfile, UserSkillScore, UserLevelHistory,
    ExerciseAttempt, LevelAssessmentTest,
)
from app.models.reminder import UserReminderPreference, ReminderDelivery
from app.models.rbac import AuditLog
from app.models.games import GameSession, XPTransaction
from app.models.reward_grant import UserRewardGrant

# Dependency order matters: children before parents
_USER_ID_SCOPED_MODELS = (
    ReminderDelivery,
    UserReminderPreference,
    Notification,
    AuditLog,
    ExerciseAttempt,
    LevelAssessmentTest,
    UserSkillScore,
    UserLevelHistory,
    UserProficiencyProfile,
    ChallengeRewardClaim,
    UserRewardGrant,
    ActivityFeed,
    UserInventory,
    WalletTransaction,
    LeaderboardEntry,
    UserWallet,
    UserAchievement,
    XPTransaction,
    GameSession,
    VocabularyReview,
    VocabularyDeck,
    UserVocabulary,
    DailyReviewSession,
    UserVocabKnowledge,
    QuestionAttempt,
    DailyActivity,
    LessonAttempt,
    LessonCompletion,
    UserCourseProgress,
    UserProgress,
    Streak,
    RefreshToken,
    UserDevice,
)


async def permanently_delete_user(db: AsyncSession, user: User) -> None:
    """Cascade-delete all data owned by `user`, then the user row itself. Caller must commit."""
    uid = user.id

    for model in _USER_ID_SCOPED_MODELS:
        await db.execute(sa_delete(model).where(model.user_id == uid))

    # UserFollowing uses follower_id / following_id instead of user_id
    await db.execute(
        sa_delete(UserFollowing).where(
            (UserFollowing.follower_id == uid) | (UserFollowing.following_id == uid)
        )
    )

    await db.delete(user)
