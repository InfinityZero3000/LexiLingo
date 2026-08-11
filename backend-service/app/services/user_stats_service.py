from datetime import date, datetime, timedelta, timezone

from sqlalchemy import delete as sa_delete
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.games import GameSession, XPTransaction
from app.models.gamification import (
    ActivityFeed,
    ChallengeRewardClaim,
    LeaderboardEntry,
    UserAchievement,
    UserFollowing,
    UserInventory,
    UserWallet,
    WalletTransaction,
)
from app.models.notification import Notification
from app.models.proficiency import (
    ExerciseAttempt,
    LevelAssessmentTest,
    UserLevelHistory,
    UserProficiencyProfile,
    UserSkillScore,
)
from app.models.progress import (
    DailyActivity,
    DailyReviewSession,
    LessonAttempt,
    LessonCompletion,
    QuestionAttempt,
    Streak,
    UserCourseProgress,
    UserProgress,
    UserVocabKnowledge,
)
from app.models.rbac import AuditLog
from app.models.reminder import ReminderDelivery, UserReminderPreference
from app.models.reward_grant import UserRewardGrant
from app.models.user import RefreshToken, User, UserDevice
from app.models.vocabulary import UserVocabulary, VocabularyDeck, VocabularyReview
from app.schemas.level import (
    UserStatsResponse,
    WeeklyActivityData,
    WeeklyActivityResponse,
)
from app.services.level_service import LevelService


async def get_user_stats(db: AsyncSession, user: User) -> UserStatsResponse:
    level_status = LevelService.calculate_level_status(user.total_xp)

    def count(column, *filters):
        return select(func.count(column)).where(*filters).scalar_subquery()

    stats = (
        await db.execute(
            select(
                count(
                    UserCourseProgress.id,
                    UserCourseProgress.user_id == user.id,
                ).label("courses_enrolled"),
                count(
                    UserCourseProgress.id,
                    UserCourseProgress.user_id == user.id,
                    UserCourseProgress.progress_percentage >= 100,
                ).label("courses_completed"),
                count(
                    LessonCompletion.id,
                    LessonCompletion.user_id == user.id,
                    LessonCompletion.is_passed.is_(True),
                ).label("lessons_completed"),
                select(func.coalesce(func.sum(LessonAttempt.time_spent_ms), 0))
                .where(LessonAttempt.user_id == user.id)
                .scalar_subquery()
                .label("study_time_ms"),
                select(Streak.current_streak)
                .where(Streak.user_id == user.id)
                .scalar_subquery()
                .label("current_streak"),
                select(Streak.longest_streak)
                .where(Streak.user_id == user.id)
                .scalar_subquery()
                .label("longest_streak"),
                count(
                    UserVocabulary.id,
                    UserVocabulary.user_id == user.id,
                ).label("words_learned"),
                count(
                    UserVocabulary.id,
                    UserVocabulary.user_id == user.id,
                    UserVocabulary.status == "mastered",
                ).label("words_mastered"),
                count(
                    UserAchievement.id,
                    UserAchievement.user_id == user.id,
                ).label("achievements_unlocked"),
                select(UserWallet.gems)
                .where(UserWallet.user_id == user.id)
                .scalar_subquery()
                .label("total_gems"),
            )
        )
    ).one()

    return UserStatsResponse(
        total_xp=user.total_xp,
        level=level_status,
        courses_enrolled=stats.courses_enrolled or 0,
        courses_completed=stats.courses_completed or 0,
        lessons_completed=stats.lessons_completed or 0,
        total_study_time=int((stats.study_time_ms or 0) / 60000),
        current_streak=stats.current_streak or 0,
        longest_streak=stats.longest_streak or 0,
        words_learned=stats.words_learned or 0,
        words_mastered=stats.words_mastered or 0,
        achievements_unlocked=stats.achievements_unlocked or 0,
        total_gems=stats.total_gems or 0,
    )


async def get_weekly_activity(db: AsyncSession, user: User) -> WeeklyActivityResponse:
    today = datetime.now(timezone.utc).date()
    week_ago = today - timedelta(days=6)
    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    range_start = datetime.combine(week_ago, datetime.min.time())
    range_end = datetime.combine(today + timedelta(days=1), datetime.min.time())
    rows = (
        await db.execute(
            select(
                func.date(LessonAttempt.finished_at).label("day"),
                func.count(LessonAttempt.id).label("count"),
                func.coalesce(func.sum(LessonAttempt.xp_earned), 0).label("xp"),
                func.coalesce(func.sum(LessonAttempt.time_spent_ms), 0).label("time"),
            )
            .where(
                LessonAttempt.user_id == user.id,
                LessonAttempt.finished_at >= range_start,
                LessonAttempt.finished_at < range_end,
                LessonAttempt.passed.is_(True),
            )
            .group_by(func.date(LessonAttempt.finished_at))
        )
    ).all()
    activity_by_day = {
        date.fromisoformat(row.day) if isinstance(row.day, str) else row.day: row
        for row in rows
    }

    week_data: list[WeeklyActivityData] = []
    total_xp = total_lessons = total_study_time = 0

    for i in range(7):
        day_date = week_ago + timedelta(days=i)
        row = activity_by_day.get(day_date)

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
