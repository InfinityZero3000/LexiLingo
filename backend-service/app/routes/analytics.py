"""
Admin Analytics Routes
Endpoints for dashboard charts, user metrics, content performance, and vocabulary analytics.
"""

from datetime import datetime, timedelta
from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_, case
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.dependencies import get_current_admin
from app.models.user import User
from app.models.course import Course, Lesson
from app.models.progress import LessonCompletion, DailyActivity, UserCourseProgress
from app.models.vocabulary import VocabularyItem, UserVocabulary
from app.models.gamification import Achievement, UserAchievement

router = APIRouter(prefix="/admin/analytics", tags=["Analytics"])


# ============================================================================
# Dashboard Analytics
# ============================================================================

@router.get("/dashboard/kpis")
async def get_dashboard_kpis(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get key performance indicators for the main dashboard.
    """
    # Total users
    total_users = await db.scalar(select(func.count(User.id)))

    # Active users in last 7 days
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    active_users_7d = await db.scalar(
        select(func.count(func.distinct(DailyActivity.user_id)))
        .where(DailyActivity.activity_date >= seven_days_ago.date())
    )

    # Total courses
    total_courses = await db.scalar(
        select(func.count(Course.id)).where(Course.is_published == True)
    )

    # Total lessons completed today
    today = datetime.utcnow().date()
    lessons_completed_today = await db.scalar(
        select(func.count(LessonCompletion.id))
        .where(func.date(LessonCompletion.completed_at) == today)
    )

    # Average DAU in last 30 days
    thirty_days_ago = datetime.utcnow() - timedelta(days=30)
    dau_data = await db.execute(
        select(
            DailyActivity.activity_date,
            func.count(func.distinct(DailyActivity.user_id)).label("dau")
        )
        .where(DailyActivity.activity_date >= thirty_days_ago.date())
        .group_by(DailyActivity.activity_date)
    )
    dau_list = [row.dau for row in dau_data.fetchall()]
    avg_dau_30d = sum(dau_list) / len(dau_list) if dau_list else 0

    return {
        "kpis": {
            "total_users": total_users or 0,
            "active_users_7d": active_users_7d or 0,
            "total_courses": total_courses or 0,
            "total_lessons_completed_today": lessons_completed_today or 0,
            "avg_dau_30d": avg_dau_30d,
        }
    }


@router.get("/dashboard/user-growth")
async def get_user_growth(
    days: int = Query(30, ge=7, le=90),
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get user growth data for the specified number of days.
    Returns daily new users and cumulative total users.
    """
    end_date = datetime.utcnow().date()
    start_date = end_date - timedelta(days=days)

    # Get daily registrations
    daily_signups = await db.execute(
        select(
            func.date(User.created_at).label("date"),
            func.count(User.id).label("new_users")
        )
        .where(func.date(User.created_at) >= start_date)
        .group_by(func.date(User.created_at))
        .order_by(func.date(User.created_at))
    )

    signup_dict = {row.date: row.new_users for row in daily_signups.fetchall()}

    # Get total users up to start date
    initial_total = await db.scalar(
        select(func.count(User.id))
        .where(func.date(User.created_at) < start_date)
    ) or 0

    # Build daily data
    data = []
    running_total = initial_total
    current_date = start_date

    while current_date <= end_date:
        new_users = signup_dict.get(current_date, 0)
        running_total += new_users
        data.append({
            "date": current_date.isoformat(),
            "new_users": new_users,
            "total_users": running_total,
        })
        current_date += timedelta(days=1)

    return {"data": data}


@router.get("/dashboard/engagement")
async def get_engagement(
    weeks: int = Query(12, ge=4, le=52),
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get DAU, WAU, MAU engagement metrics by week.
    """
    end_date = datetime.utcnow().date()
    start_date = end_date - timedelta(weeks=weeks)

    data = []

    for i in range(weeks):
        week_end = end_date - timedelta(weeks=i)
        week_start = week_end - timedelta(days=7)

        # DAU (average for the week)
        dau_result = await db.execute(
            select(
                DailyActivity.activity_date,
                func.count(func.distinct(DailyActivity.user_id)).label("users")
            )
            .where(
                and_(
                    DailyActivity.activity_date >= week_start,
                    DailyActivity.activity_date < week_end
                )
            )
            .group_by(DailyActivity.activity_date)
        )
        dau_values = [row.users for row in dau_result.fetchall()]
        avg_dau = sum(dau_values) / len(dau_values) if dau_values else 0

        # WAU (unique users in the week)
        wau = await db.scalar(
            select(func.count(func.distinct(DailyActivity.user_id)))
            .where(
                and_(
                    DailyActivity.activity_date >= week_start,
                    DailyActivity.activity_date < week_end
                )
            )
        ) or 0

        # MAU (unique users in last 30 days from week_end)
        mau_start = week_end - timedelta(days=30)
        mau = await db.scalar(
            select(func.count(func.distinct(DailyActivity.user_id)))
            .where(
                and_(
                    DailyActivity.activity_date >= mau_start,
                    DailyActivity.activity_date < week_end
                )
            )
        ) or 0

        data.insert(0, {
            "week": f"{week_start.strftime('%d/%m')} - {week_end.strftime('%d/%m')}",
            "dau": int(avg_dau),
            "wau": wau,
            "mau": mau,
        })

    return {"data": data}


@router.get("/dashboard/course-popularity")
async def get_course_popularity(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get top 6 courses by enrollment count.
    """
    result = await db.execute(
        select(
            Course.title,
            func.count(UserCourseProgress.id).label("enrollments")
        )
        .join(UserCourseProgress, UserCourseProgress.course_id == Course.id)
        .where(Course.is_published == True)
        .group_by(Course.id, Course.title)
        .order_by(func.count(UserCourseProgress.id).desc())
        .limit(6)
    )

    data = [
        {
            "course_title": row.title,
            "enrollments": row.enrollments,
        }
        for row in result.fetchall()
    ]

    return {"data": data}


@router.get("/dashboard/completion-funnel")
async def get_completion_funnel(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get course completion funnel: Enrolled → Started → 50% → Completed.
    """
    # Total enrollments
    total_enrolled = await db.scalar(
        select(func.count(UserCourseProgress.id))
    ) or 1  # Avoid division by zero

    # Started (has progress > 0)
    started = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(UserCourseProgress.progress_percentage > 0)
    ) or 0

    # 50% complete
    halfway = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(UserCourseProgress.progress_percentage >= 50)
    ) or 0

    # Completed
    completed = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(UserCourseProgress.progress_percentage >= 100)
    ) or 0

    data = [
        {
            "stage": "Đăng ký",
            "count": total_enrolled,
            "percentage": 100.0,
        },
        {
            "stage": "Bắt đầu",
            "count": started,
            "percentage": (started / total_enrolled * 100) if total_enrolled else 0,
        },
        {
            "stage": "50% hoàn thành",
            "count": halfway,
            "percentage": (halfway / total_enrolled * 100) if total_enrolled else 0,
        },
        {
            "stage": "Hoàn thành",
            "count": completed,
            "percentage": (completed / total_enrolled * 100) if total_enrolled else 0,
        },
    ]

    return {"data": data}


# ============================================================================
# User Analytics
# ============================================================================

@router.get("/user-metrics")
async def get_user_metrics(
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get user engagement metrics: DAU, WAU, MAU, signups.
    """
    if end_date:
        end = datetime.fromisoformat(end_date).date()
    else:
        end = datetime.utcnow().date()

    if start_date:
        start = datetime.fromisoformat(start_date).date()
    else:
        start = end - timedelta(days=30)

    # DAU (average)
    dau_result = await db.execute(
        select(
            DailyActivity.activity_date,
            func.count(func.distinct(DailyActivity.user_id)).label("users")
        )
        .where(
            and_(
                DailyActivity.activity_date >= start,
                DailyActivity.activity_date <= end
            )
        )
        .group_by(DailyActivity.activity_date)
    )
    dau_values = [row.users for row in dau_result.fetchall()]
    avg_dau = sum(dau_values) / len(dau_values) if dau_values else 0

    # WAU (last 7 days from end)
    wau_start = end - timedelta(days=7)
    wau = await db.scalar(
        select(func.count(func.distinct(DailyActivity.user_id)))
        .where(
            and_(
                DailyActivity.activity_date >= wau_start,
                DailyActivity.activity_date <= end
            )
        )
    ) or 0

    # MAU (last 30 days from end)
    mau_start = end - timedelta(days=30)
    mau = await db.scalar(
        select(func.count(func.distinct(DailyActivity.user_id)))
        .where(
            and_(
                DailyActivity.activity_date >= mau_start,
                DailyActivity.activity_date <= end
            )
        )
    ) or 0

    # Total signups in date range
    signups = await db.scalar(
        select(func.count(User.id))
        .where(
            and_(
                func.date(User.created_at) >= start,
                func.date(User.created_at) <= end
            )
        )
    ) or 0

    return {
        "metrics": {
            "dau": int(avg_dau),
            "wau": wau,
            "mau": mau,
            "total_signups": signups,
            "avg_session_duration": 0,  # Placeholder - implement if session tracking exists
        }
    }


@router.get("/retention-cohorts")
async def get_retention_cohorts(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get cohort retention analysis.
    Cohorts are grouped by signup week.
    """
    # Get cohorts from last 12 weeks
    end_date = datetime.utcnow().date()
    start_date = end_date - timedelta(weeks=12)

    # This is a simplified version - full implementation would require more complex queries
    # For MVP, return empty or sample data
    return {
        "cohorts": [
            {
                "cohort_date": (start_date + timedelta(weeks=i)).isoformat(),
                "users": 0,
                "d1_retention": 0.0,
                "d7_retention": 0.0,
                "d30_retention": 0.0,
            }
            for i in range(12)
        ]
    }


# ============================================================================
# Content Performance
# ============================================================================

@router.get("/content-performance")
async def get_content_performance(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get course and lesson performance metrics.
    """
    # Course performance
    course_result = await db.execute(
        select(
            Course.id,
            Course.title,
            func.count(func.distinct(UserCourseProgress.id)).label("enrollments"),
            func.count(
                case((UserCourseProgress.progress_percentage >= 100, 1))
            ).label("completions"),
        )
        .outerjoin(UserCourseProgress, UserCourseProgress.course_id == Course.id)
        .where(Course.is_published == True)
        .group_by(Course.id, Course.title)
    )

    courses = []
    for row in course_result.fetchall():
        completion_rate = (row.completions / row.enrollments * 100) if row.enrollments > 0 else 0
        courses.append({
            "course_id": str(row.id),
            "course_title": row.title,
            "enrollments": row.enrollments,
            "completions": row.completions,
            "completion_rate": completion_rate,
            "avg_score": 0.0,  # Placeholder
            "avg_time_minutes": 0,  # Placeholder
        })

    # Lesson difficulty (simplified - would need LessonAttempt data for full metrics)
    lessons = []  # Placeholder for MVP

    return {
        "courses": courses,
        "lessons": lessons,
    }


# ============================================================================
# Vocabulary Effectiveness
# ============================================================================

@router.get("/vocabulary-effectiveness")
async def get_vocabulary_effectiveness(
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get vocabulary mastery statistics and hardest words.
    """
    # Total vocabulary items
    total_words = await db.scalar(
        select(func.count(VocabularyItem.id))
    ) or 0

    # Average mastery rate (users with mastery_level >= 3)
    total_user_vocab = await db.scalar(
        select(func.count(UserVocabulary.id))
    ) or 1

    mastered_count = await db.scalar(
        select(func.count(UserVocabulary.id))
        .where(UserVocabulary.mastery_level >= 3)
    ) or 0

    avg_mastery_rate = (mastered_count / total_user_vocab * 100) if total_user_vocab > 0 else 0

    # Average reviews to master
    avg_reviews = await db.scalar(
        select(func.avg(UserVocabulary.review_count))
        .where(UserVocabulary.mastery_level >= 3)
    ) or 0

    # Hardest words (lowest mastery rate)
    hardest_result = await db.execute(
        select(
            VocabularyItem.word,
            func.count(UserVocabulary.id).label("total"),
            func.count(
                case((UserVocabulary.mastery_level >= 3, 1))
            ).label("mastered")
        )
        .join(UserVocabulary, UserVocabulary.vocabulary_id == VocabularyItem.id)
        .group_by(VocabularyItem.id, VocabularyItem.word)
        .having(func.count(UserVocabulary.id) >= 5)  # At least 5 users
        .order_by((func.count(case((UserVocabulary.mastery_level >= 3, 1))) / func.count(UserVocabulary.id)).asc())
        .limit(10)
    )

    hardest_words = []
    for row in hardest_result.fetchall():
        mastery_rate = (row.mastered / row.total * 100) if row.total > 0 else 0
        hardest_words.append({
            "word": row.word,
            "mastery_rate": mastery_rate,
            "avg_reviews": 0,  # Placeholder - would need per-word review data
        })

    return {
        "total_words": total_words,
        "avg_mastery_rate": avg_mastery_rate,
        "avg_reviews_to_master": avg_reviews,
        "hardest_words": hardest_words,
    }
