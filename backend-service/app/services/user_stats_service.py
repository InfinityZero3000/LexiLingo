from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gamification import UserAchievement, UserWallet
from app.models.progress import (
    DailyActivity,
    LessonAttempt,
    LessonCompletion,
    Streak,
    UserCourseProgress,
)
from app.models.user import User
from app.models.vocabulary import UserVocabulary
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
                    UserVocabulary.total_reviews > 0,
                ).label("words_reviewed"),
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
        words_reviewed=stats.words_reviewed or 0,
        words_mastered=stats.words_mastered or 0,
        achievements_unlocked=stats.achievements_unlocked or 0,
        total_gems=stats.total_gems or 0,
    )


_DAY_NAMES = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


async def get_weekly_activity(db: AsyncSession, user: User) -> WeeklyActivityResponse:
    today = datetime.now(timezone.utc).date()
    week_ago = today - timedelta(days=6)

    rows = (
        await db.execute(
            select(
                DailyActivity.activity_date,
                func.sum(DailyActivity.xp_earned).label("xp"),
                func.sum(DailyActivity.lessons_completed).label("lessons"),
                func.sum(DailyActivity.study_time_minutes).label("minutes"),
                func.sum(DailyActivity.vocabulary_reviewed).label("vocab"),
            )
            .where(
                DailyActivity.user_id == user.id,
                DailyActivity.activity_date >= week_ago,
                DailyActivity.activity_date <= today,
            )
            .group_by(DailyActivity.activity_date)
        )
    ).all()
    activity_by_day = {row.activity_date: row for row in rows}

    week_data: list[WeeklyActivityData] = []
    for i in range(7):
        day_date = week_ago + timedelta(days=i)
        row = activity_by_day.get(day_date)
        week_data.append(WeeklyActivityData(
            day=_DAY_NAMES[day_date.weekday()],
            date=day_date.isoformat(),
            xp=int(row.xp or 0) if row else 0,
            lessons=int(row.lessons or 0) if row else 0,
            study_time=int(row.minutes or 0) if row else 0,
            vocabulary=int(row.vocab or 0) if row else 0,
        ))

    return WeeklyActivityResponse(
        week_data=week_data,
        total_xp=sum(d.xp for d in week_data),
        total_lessons=sum(d.lessons for d in week_data),
        total_study_time=sum(d.study_time for d in week_data),
        total_vocabulary=sum(d.vocabulary for d in week_data),
    )
