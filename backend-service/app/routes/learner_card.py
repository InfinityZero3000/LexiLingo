"""Private service-to-service learner-card route.

One aggregate snapshot of everything Lexi may need to answer "who am I,
where am I, what should I study next" — assembled in a single request so
ai-service never has to fan out across user/proficiency/course endpoints on
the chat hot path. ai-service caches the result, which is what makes this
CAG-shaped rather than RAG-shaped: the facts are preloaded into the prompt,
not retrieved per turn.
"""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.course import Course
from app.models.proficiency import UserProficiencyProfile, UserSkillScore
from app.models.progress import Streak, UserCourseProgress
from app.models.user import User
from app.routes.learner_state import require_learner_state_service

router = APIRouter(prefix="/internal/learner-card", tags=["Internal Learner Card"])

_CEFR_ORDER = ["A1", "A2", "B1", "B2", "C1", "C2"]
_MAX_ENROLLED = 6
_MAX_SUGGESTED = 4


def _level_index(level: Any) -> int:
    try:
        return _CEFR_ORDER.index(str(level).strip().upper())
    except ValueError:
        return 0


@router.get("/{user_id}")
async def get_learner_card(
    user_id: str,
    _caller: str = Depends(require_learner_state_service),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    try:
        uid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="invalid user_id")

    user = await db.scalar(select(User).where(User.id == uid))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="user not found")

    profile = await db.scalar(
        select(UserProficiencyProfile).where(UserProficiencyProfile.user_id == uid)
    )
    assessed_level = (profile.assessed_level if profile else None) or user.level or "A1"

    skills: dict[str, dict[str, Any]] = {}
    if profile is not None:
        rows = await db.scalars(
            select(UserSkillScore).where(UserSkillScore.profile_id == profile.id)
        )
        for row in rows:
            skills[row.skill.value] = {
                "score": round(float(row.score or 0.0), 1),
                "level": row.estimated_level,
                "exercises": int(row.exercises_completed or 0),
            }

    streak = await db.scalar(select(Streak).where(Streak.user_id == uid))

    enrolled_rows = list(
        await db.execute(
            select(UserCourseProgress, Course)
            .join(Course, Course.id == UserCourseProgress.course_id)
            .where(UserCourseProgress.user_id == uid)
            .order_by(UserCourseProgress.last_activity_at.desc())
            .limit(_MAX_ENROLLED)
        )
    )
    enrolled = [
        {
            "course_id": str(course.id),
            "title": course.title,
            "level": course.level,
            "progress": round(float(progress.progress_percentage or 0.0), 1),
            "lessons_completed": int(progress.lessons_completed or 0),
            "total_lessons": int(course.total_lessons or 0),
        }
        for progress, course in enrolled_rows
    ]
    enrolled_ids = {row["course_id"] for row in enrolled}

    # ponytail: level-proximity sort, not the RecGraph ranker. Calling the
    # ranker here would mean backend -> ai-service -> backend inside a chat
    # turn the learner is waiting on. Swap in RecommendationClient.rank if the
    # ordering ever needs to beat "closest to your level first".
    catalog = list(
        await db.scalars(select(Course).where(Course.is_published.is_(True)).limit(200))
    )
    learner_index = _level_index(assessed_level)
    suggested = sorted(
        (course for course in catalog if str(course.id) not in enrolled_ids),
        key=lambda course: (
            abs(_level_index(course.level) - learner_index),
            _level_index(course.level),
        ),
    )[:_MAX_SUGGESTED]

    return {
        "user_id": str(uid),
        "display_name": user.display_name or user.username,
        "username": user.username,
        "native_language": user.native_language,
        "target_language": user.target_language,
        "member_since": user.created_at.date().isoformat() if user.created_at else None,
        "cefr_level": user.level,
        "assessed_level": assessed_level,
        "overall_score": round(float(profile.overall_score or 0.0), 1) if profile else 0.0,
        "goal": user.goal,
        "interest": user.interest,
        "total_xp": int(user.total_xp or 0),
        "numeric_level": int(user.numeric_level or 1),
        "rank": user.rank,
        "streak_days": int(streak.current_streak or 0) if streak else 0,
        "lessons_completed": int(profile.total_lessons_completed or 0) if profile else 0,
        "exercises_completed": int(profile.total_exercises_completed or 0) if profile else 0,
        "skills": skills,
        "enrolled_courses": enrolled,
        "suggested_courses": [
            {
                "course_id": str(course.id),
                "title": course.title,
                "level": course.level,
                "description": (course.description or "")[:200],
                "thumbnail_url": course.thumbnail_url,
                "total_lessons": int(course.total_lessons or 0),
                "estimated_duration": int(course.estimated_duration or 0),
            }
            for course in suggested
        ],
    }
