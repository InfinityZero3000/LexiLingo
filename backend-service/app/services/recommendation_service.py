"""Profile and candidate generation for the recommender.

backend-service owns every source of truth the recommender reads, so candidate
generation happens here in SQL; ranking happens in ai-service (RecGraph).
"""

from __future__ import annotations

import logging
import math
import uuid
from collections import defaultdict
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.redis import get_redis
from app.crud.vocabulary import _vocab_concept_id
from app.models.course import Course, Lesson
from app.models.learner_state import LearnerConceptState, LearnerStateProfile
from app.models.product_event import ProductEvent
from app.models.proficiency import UserProficiencyProfile, UserSkillScore
from app.models.progress import LessonCompletion, UserCourseProgress
from app.models.vocabulary import UserVocabulary, VocabularyItem
from app.routes.youtube import CURATED_CHANNELS
from app.services.learner_state import get_due_concepts_for_user

logger = logging.getLogger(__name__)

# Weight of each interaction when building topic affinity. A completion says
# far more about interest than an impression does.
ACTION_WEIGHTS = {
    "complete": 1.0,
    "start": 0.7,
    "review": 0.7,
    "open": 0.4,
    "impression": 0.05,
    "skip": -0.5,
}
AFFINITY_HALF_LIFE_DAYS = 14.0
AFFINITY_WINDOW_DAYS = 60
# ponytail: events are aggregated in Python from a bounded window rather than
# in SQL, so this works identically on SQLite (tests) and JSONB. Materialize
# into a user_topic_affinity table when this scan shows up in slow queries.
AFFINITY_EVENT_LIMIT = 2000

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

    states = list(
        await db.scalars(
            select(LearnerConceptState).where(LearnerConceptState.user_id == user_id)
        )
    )
    due = await get_due_concepts_for_user(db, user_id)
    epoch = await db.scalar(
        select(LearnerStateProfile.state_epoch).where(
            LearnerStateProfile.user_id == user_id
        )
    )

    return {
        "level": level,
        "weak_skills": [row.skill.value for row in skill_rows],
        "mastery": {row.concept_id: row.mastery_probability for row in states},
        "due_concepts": [row.concept_id for row in due],
        "topic_affinity": await build_topic_affinity(db, user_id),
        "state_epoch": int(epoch or 0),
        "interaction_epoch": await _get_interaction_epoch(user_id),
        "required_types": ["course", "lesson", "vocab", "video"],
    }


async def build_topic_affinity(
    db: AsyncSession, user_id: uuid.UUID, *, now: datetime | None = None
) -> dict[str, float]:
    """Time-decayed topic preference, normalized to [0,1].

    This is the "topic the learner picks most often" signal: every surface
    reports `content_interaction` with a `topic`, and recent picks outweigh old
    ones on a 14-day half-life.
    """
    now = now or datetime.now(UTC)
    since = now - timedelta(days=AFFINITY_WINDOW_DAYS)
    rows = list(
        await db.scalars(
            select(ProductEvent)
            .where(
                ProductEvent.user_id == user_id,
                ProductEvent.event_name == "content_interaction",
                ProductEvent.created_at >= since,
            )
            .order_by(ProductEvent.created_at.desc())
            .limit(AFFINITY_EVENT_LIMIT)
        )
    )

    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        properties = row.properties or {}
        topic = str(properties.get("topic") or "").strip().lower()
        if not topic:
            continue
        weight = ACTION_WEIGHTS.get(str(properties.get("action") or "open"), 0.4)
        age_days = max((now - _as_utc(row.created_at)).total_seconds() / 86400.0, 0.0)
        decay = math.exp(-age_days * math.log(2) / AFFINITY_HALF_LIFE_DAYS)
        totals[topic] += weight * decay

    positives = [value for value in totals.values() if value > 0]
    if not positives:
        return {}
    peak = max(positives)
    return {
        topic: round(value / peak, 4) for topic, value in totals.items() if value > 0
    }


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


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)
