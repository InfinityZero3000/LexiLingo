from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select, delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import (
    ActivityFeed, ChallengeRewardClaim, LeaderboardEntry,
    UserAchievement, UserFollowing, UserInventory, UserWallet, WalletTransaction,
)
from app.models.games import GameSession, XPTransaction
from app.models.notification import Notification
from app.models.proficiency import (
    ExerciseAttempt, LevelAssessmentTest, UserLevelHistory,
    UserProficiencyProfile, UserSkillScore,
)
from app.models.progress import (
    DailyActivity, DailyReviewSession, LessonAttempt, LessonCompletion,
    QuestionAttempt, Streak, UserCourseProgress, UserProgress, UserVocabKnowledge,
)
from app.models.rbac import AuditLog
from app.models.reminder import ReminderDelivery, UserReminderPreference
from app.models.reward_grant import UserRewardGrant
from app.models.user import User, RefreshToken, UserDevice
from app.models.vocabulary import UserVocabulary, VocabularyDeck, VocabularyReview
from app.schemas.level import (
    UserStatsResponse, WeeklyActivityData, WeeklyActivityResponse,
)
from app.services.level_service import LevelService


async def get_user_stats(db: AsyncSession, user: User) -> UserStatsResponse:
    level_status = LevelService.calculate_level_status(user.total_xp)

    courses_enrolled = (await db.execute(
        select(func.count(UserCourseProgress.id)).where(UserCourseProgress.user_id == user.id)
    )).scalar() or 0

    courses_completed = (await db.execute(
        select(func.count(UserCourseProgress.id)).where(
            UserCourseProgress.user_id == user.id,
            UserCourseProgress.progress_percentage >= 100,
        )
    )).scalar() or 0

    lessons_completed = (await db.execute(
        select(func.count(LessonCompletion.id)).where(
            LessonCompletion.user_id == user.id,
            LessonCompletion.is_passed.is_(True),
        )
    )).scalar() or 0

    raw_time = (await db.execute(
        select(func.sum(LessonAttempt.time_spent_ms)).where(LessonAttempt.user_id == user.id)
    )).scalar() or 0
    total_study_time = int(raw_time / 60000) if raw_time else 0

    streak = (await db.execute(
        select(Streak).where(Streak.user_id == user.id)
    )).scalar_one_or_none()
    current_streak = streak.current_streak if streak else 0
    longest_streak = streak.longest_streak if streak else 0

    words_learned = (await db.execute(
        select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == user.id)
    )).scalar() or 0

    words_mastered = (await db.execute(
        select(func.count(UserVocabulary.id)).where(
            UserVocabulary.user_id == user.id,
            UserVocabulary.status == "mastered",
        )
    )).scalar() or 0

    achievements_unlocked = (await db.execute(
        select(func.count(UserAchievement.id)).where(UserAchievement.user_id == user.id)
    )).scalar() or 0

    wallet = (await db.execute(
        select(UserWallet).where(UserWallet.user_id == user.id)
    )).scalar_one_or_none()
    total_gems = wallet.gems if wallet else 0

    return UserStatsResponse(
        total_xp=user.total_xp,
        level=level_status,
        courses_enrolled=courses_enrolled,
        courses_completed=courses_completed,
        lessons_completed=lessons_completed,
        total_study_time=total_study_time,
        current_streak=current_streak,
        longest_streak=longest_streak,
        words_learned=words_learned,
        words_mastered=words_mastered,
        achievements_unlocked=achievements_unlocked,
        total_gems=total_gems,
    )


async def get_weekly_activity(db: AsyncSession, user: User) -> WeeklyActivityResponse:
    today = datetime.now(timezone.utc).date()
    week_ago = today - timedelta(days=6)
    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    week_data: list[WeeklyActivityData] = []
    total_xp = total_lessons = total_study_time = 0

    for i in range(7):
        day_date = week_ago + timedelta(days=i)
        day_start = datetime.combine(day_date, datetime.min.time())
        day_end = datetime.combine(day_date, datetime.max.time())

        row = (await db.execute(
            select(
                func.count(LessonAttempt.id).label("count"),
                func.coalesce(func.sum(LessonAttempt.xp_earned), 0).label("xp"),
                func.coalesce(func.sum(LessonAttempt.time_spent_ms), 0).label("time"),
            ).where(
                LessonAttempt.user_id == user.id,
                LessonAttempt.finished_at >= day_start,
                LessonAttempt.finished_at <= day_end,
                LessonAttempt.passed.is_(True),
            )
        )).first()

        day_lessons = int(row.count) if row and row.count else 0
        day_xp = int(row.xp) if row and row.xp else 0
        day_time = int(row.time / 60000) if row and row.time else 0

        week_data.append(WeeklyActivityData(
            day=day_names[day_date.weekday()],
            xp=day_xp,
            lessons=day_lessons,
            study_time=day_time,
        ))
        total_xp += day_xp
        total_lessons += day_lessons
        total_study_time += day_time

    return WeeklyActivityResponse(
        week_data=week_data,
        total_xp=total_xp,
        total_lessons=total_lessons,
        total_study_time=total_study_time,
    )


_DELETE_ORDER = (
    ReminderDelivery, UserReminderPreference, Notification, AuditLog,
    ExerciseAttempt, LevelAssessmentTest, UserSkillScore, UserLevelHistory,
    UserProficiencyProfile, ChallengeRewardClaim, UserRewardGrant,
    ActivityFeed, UserInventory, WalletTransaction, LeaderboardEntry,
    UserWallet, UserAchievement, XPTransaction, GameSession,
    VocabularyReview, VocabularyDeck, UserVocabulary, DailyReviewSession,
    UserVocabKnowledge, QuestionAttempt, DailyActivity, LessonAttempt,
    LessonCompletion, UserCourseProgress, UserProgress, Streak,
    RefreshToken, UserDevice,
)


async def delete_user_permanently(db: AsyncSession, user: User) -> None:
    uid = user.id
    for model in _DELETE_ORDER:
        await db.execute(sa_delete(model).where(model.user_id == uid))
    await db.execute(
        sa_delete(UserFollowing).where(
            (UserFollowing.follower_id == uid) | (UserFollowing.following_id == uid)
        )
    )
    await db.delete(user)
    await db.commit()
