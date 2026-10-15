"""Profile and candidate generation for the recommender.

backend-service owns every source of truth the recommender reads, so candidate
generation happens here in SQL; ranking happens in ai-service (RecGraph).
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.redis import get_redis
from app.crud.vocabulary import _vocab_concept_id
from app.models.course import Course, Lesson
from app.models.learner_state import LearnerConceptState, LearnerStateProfile
from app.models.proficiency import UserProficiencyProfile, UserSkillScore
from app.models.progress import LessonCompletion, UserCourseProgress
from app.models.vocabulary import UserVocabulary, VocabularyItem
from app.routes.youtube import CURATED_CHANNELS
from app.services.feature_processor import (
    INSIGHTS_CACHE_PREFIX,
    INSIGHTS_CACHE_TTL_SECONDS,
    compute_insights,
)
from app.services.learner_state import get_due_concepts_for_user

logger = logging.getLogger(__name__)

CANDIDATES_PER_TYPE = 40

# Bumped by app.routes.product_events on every content_interaction batch —
# a separate counter from LearnerStateProfile.state_epoch so browsing doesn't
# also invalidate TraceCAG's chat cache, which keys off the same epoch.
INTERACTION_EPOCH_PREFIX = "rec:interaction_epoch:"


async def _get_interaction_epoch(user_id: uuid.UUID) -> int:
    try:
        client = await get_redis()
        if client is None:
            return 0
        value = await client.get(f"{INTERACTION_EPOCH_PREFIX}{user_id}")
        return int(value) if value else 0
    except Exception as exc:  # cache must never fail the request
        logger.warning("interaction epoch read failed: %s", exc)
        return 0


async def get_assessed_level(db: AsyncSession, user_id: uuid.UUID) -> str:
    proficiency = await db.scalar(
        select(UserProficiencyProfile).where(UserProficiencyProfile.user_id == user_id)
    )
    return (proficiency.assessed_level if proficiency else None) or "A1"


async def _read_cached_insights(user_id: uuid.UUID) -> dict[str, Any] | None:
    """The Event Worker (app.tasks.event_worker) writes here after draining
    the content_interaction stream. A miss means either a first-time user or
    the worker hasn't caught up yet — the caller recomputes synchronously."""
    try:
        client = await get_redis()
        if client is None:
            return None
        raw = await client.get(f"{INSIGHTS_CACHE_PREFIX}{user_id}")
        return json.loads(raw) if raw else None
    except Exception as exc:  # cache must never fail the request
        logger.warning("insights cache read failed: %s", exc)
        return None


async def _write_cached_insights(user_id: uuid.UUID, insights: dict[str, Any]) -> None:
    """Write-through on a synchronous recompute, so a burst of requests for
    the same cold user doesn't each hit Postgres again before the worker
    would have caught up anyway."""
    try:
        client = await get_redis()
        if client is None:
            return
        await client.setex(
            f"{INSIGHTS_CACHE_PREFIX}{user_id}",
            INSIGHTS_CACHE_TTL_SECONDS,
            json.dumps(insights),
        )
    except Exception as exc:
        logger.warning("insights cache write failed: %s", exc)


async def build_profile(db: AsyncSession, user_id: uuid.UUID) -> dict[str, Any]:
    proficiency = await db.scalar(
        select(UserProficiencyProfile).where(UserProficiencyProfile.user_id == user_id)
    )
    level = (proficiency.assessed_level if proficiency else None) or "A1"

    skill_rows = []
    if proficiency:
        skill_rows = list(
            await db.scalars(
                select(UserSkillScore)
                .where(UserSkillScore.profile_id == proficiency.id)
                .order_by(UserSkillScore.score.asc())
                .limit(2)
            )
        )

    due = await get_due_concepts_for_user(db, user_id)
    epoch = await db.scalar(
        select(LearnerStateProfile.state_epoch).where(
            LearnerStateProfile.user_id == user_id
        )
    )

    insights = await _read_cached_insights(user_id)
    if insights is None:
        insights = await compute_insights(db, user_id, level=level)
        await _write_cached_insights(user_id, insights)

    return {
        "level": level,
        "weak_skills": [row.skill.value for row in skill_rows],
        # `mastery` is filled in by attach_mastery() once candidates are known
        # — see the note there for why it is not loaded here.
        "mastery": {},
        "due_concepts": [row.concept_id for row in due],
        "state_epoch": int(epoch or 0),
        "interaction_epoch": await _get_interaction_epoch(user_id),
        "required_types": ["course", "lesson", "vocab", "video"],
        **insights,
    }


async def attach_mastery(
    db: AsyncSession,
    user_id: uuid.UUID,
    profile: dict[str, Any],
    candidates: list[dict[str, Any]],
) -> dict[str, Any]:
    """Load mastery for the concepts these candidates actually reference.

    LearnerConceptState is never pruned — it is the FSRS schedule — so a
    long-running learner accumulates thousands of rows. The ranker only ever
    looks up the concept_ids carried by the candidates in front of it
    (scoring.mastery_gap), so loading the whole table meant fetching and
    shipping thousands of entries to use a couple hundred.
    """
    concept_ids = {
        concept_id
        for candidate in candidates
        for concept_id in (candidate.get("concept_ids") or [])
    }
    if not concept_ids:
        return profile

    rows = await db.scalars(
        select(LearnerConceptState).where(
            LearnerConceptState.user_id == user_id,
            LearnerConceptState.concept_id.in_(concept_ids),
        )
    )
    profile["mastery"] = {row.concept_id: row.mastery_probability for row in rows}
    return profile


async def build_candidates(
    db: AsyncSession, user_id: uuid.UUID, profile: dict[str, Any]
) -> list[dict[str, Any]]:
    return [
        *await _course_candidates(db, user_id),
        *await _lesson_candidates(db, user_id),
        *await _vocab_candidates(db, user_id, profile),
        *_video_candidates(),
    ]


async def _course_candidates(
    db: AsyncSession, user_id: uuid.UUID
) -> list[dict[str, Any]]:
    # There is no is_completed flag on an enrolment — progress_percentage is
    # the only completion signal this table carries.
    finished = set(
        await db.scalars(
            select(UserCourseProgress.course_id).where(
                UserCourseProgress.user_id == user_id,
                UserCourseProgress.progress_percentage >= 100.0,
            )
        )
    )
    courses = list(
        await db.scalars(
            select(Course)
            .where(Course.is_published.is_(True))
            .order_by(Course.created_at.desc())
            .limit(CANDIDATES_PER_TYPE * 2)
        )
    )
    return [
        {
            "item_id": str(course.id),
            "item_type": "course",
            "title": course.title,
            "description": course.description or "",
            "topic": _first_tag(course.tags),
            "level": course.level,
            "skill": course.skill,
            "tags": _as_tags(course.tags),
            "concept_ids": [],
            "payload": {"thumbnail_url": course.thumbnail_url},
        }
        for course in courses
        if course.id not in finished
    ][:CANDIDATES_PER_TYPE]


async def _lesson_candidates(
    db: AsyncSession, user_id: uuid.UUID
) -> list[dict[str, Any]]:
    completed = set(
        await db.scalars(
            select(LessonCompletion.lesson_id).where(
                LessonCompletion.user_id == user_id
            )
        )
    )
    enrolled = list(
        await db.scalars(
            select(UserCourseProgress.course_id).where(
                UserCourseProgress.user_id == user_id
            )
        )
    )
    if not enrolled:
        return []

    lessons = list(
        await db.scalars(
            select(Lesson)
            .where(Lesson.course_id.in_(enrolled), Lesson.is_published.is_(True))
            .order_by(Lesson.order_index.asc())
            .limit(CANDIDATES_PER_TYPE * 3)
        )
    )
    return [
        {
            "item_id": str(lesson.id),
            "item_type": "lesson",
            "title": lesson.title,
            "description": lesson.description or "",
            "topic": None,
            "level": None,
            "skill": lesson.skill,
            "tags": [],
            "concept_ids": [],
            "payload": {"course_id": str(lesson.course_id)},
        }
        for lesson in lessons
        # A lesson without exercises is unplayable — recommending one is a
        # dead end the learner cannot act on.
        if lesson.id not in completed and lesson.exercise_count > 0
    ][:CANDIDATES_PER_TYPE]


async def _vocab_candidates(
    db: AsyncSession, user_id: uuid.UUID, profile: dict[str, Any]
) -> list[dict[str, Any]]:
    now = datetime.now(UTC)
    due_rows = list(
        await db.scalars(
            select(UserVocabulary)
            .where(
                UserVocabulary.user_id == user_id,
                UserVocabulary.next_review_date <= now,
            )
            .order_by(UserVocabulary.next_review_date.asc())
            .limit(CANDIDATES_PER_TYPE)
        )
    )
    due_ids = [row.vocabulary_id for row in due_rows]
    items = list(
        await db.scalars(
            select(VocabularyItem).where(VocabularyItem.id.in_(due_ids))
        )
    ) if due_ids else []

    if len(items) < CANDIDATES_PER_TYPE:
        known = set(
            await db.scalars(
                select(UserVocabulary.vocabulary_id).where(
                    UserVocabulary.user_id == user_id
                )
            )
        )
        fresh = list(
            await db.scalars(
                select(VocabularyItem)
                .where(VocabularyItem.difficulty_level == profile.get("level", "A1"))
                .limit(CANDIDATES_PER_TYPE * 2)
            )
        )
        items += [item for item in fresh if item.id not in known]

    return [
        {
            "item_id": str(item.id),
            "item_type": "vocab",
            "title": item.word,
            "description": item.definition or "",
            "topic": _first_tag(item.tags),
            "level": _level_value(item.difficulty_level),
            "skill": "vocabulary",
            "tags": _as_tags(item.tags),
            "concept_ids": [_vocab_concept_id(item.word)],
            "payload": {"pronunciation": item.pronunciation},
        }
        for item in items[:CANDIDATES_PER_TYPE]
    ]


def _video_candidates() -> list[dict[str, Any]]:
    # ponytail: curated channels only. YouTube search results are not stored,
    # so a per-video candidate would burn API quota on every request; wire real
    # videos in once they are cached in api_cache_entries.
    return [
        {
            "item_id": channel["id"],
            "item_type": "video",
            "title": channel["name"],
            "description": channel.get("description", ""),
            "topic": channel.get("category"),
            "level": str(channel.get("level", "")).split("-")[0] or None,
            "skill": "listening",
            "tags": [channel.get("category", "")],
            "concept_ids": [],
            "payload": {"channel_id": channel["id"]},
        }
        for channel in CURATED_CHANNELS
    ]


def _as_tags(raw: Any) -> list[str]:
    if isinstance(raw, list):
        return [str(tag).strip().lower() for tag in raw if str(tag).strip()]
    return []


def _first_tag(raw: Any) -> str | None:
    tags = _as_tags(raw)
    return tags[0] if tags else None


def _level_value(level: Any) -> str | None:
    return getattr(level, "value", level)
