"""Deterministic CEFR/topic curriculum planning."""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Iterable

from api.models.content_agent import (
    CEFR_LEVEL_ORDER,
    CEFRLevel,
    ContentUsage,
    GenerationRequest,
    NormalizedSourceRecord,
    PartOfSpeech,
)


class InsufficientVocabularyError(ValueError):
    """Raised when a selected level cannot fill one valid lesson."""


@dataclass(frozen=True)
class PlannedLesson:
    title: str
    order_index: int
    level: CEFRLevel
    topic: str
    vocabulary: tuple[NormalizedSourceRecord, ...]


@dataclass(frozen=True)
class PlannedUnit:
    title: str
    order_index: int
    topic: str
    lessons: tuple[PlannedLesson, ...]


@dataclass(frozen=True)
class PlannedCourse:
    title: str
    description: str
    level: CEFRLevel
    units: tuple[PlannedUnit, ...]


@dataclass(frozen=True)
class CurriculumPlan:
    courses: tuple[PlannedCourse, ...]
    catalog_size: int
    rejected_low_confidence: int


def _topic_slug(value: str) -> str:
    slug = re.sub(r"[^\w]+", "_", value.casefold()).strip("_")
    return slug or "general"


def _title(value: str) -> str:
    return value.replace("_", " ").strip().title()


def _identity(record: NormalizedSourceRecord) -> tuple[str, PartOfSpeech]:
    return (record.word or "", record.part_of_speech)


def _preference(record: NormalizedSourceRecord) -> tuple[int, int, int, str]:
    usage_rank = {
        ContentUsage.METADATA_ONLY: 0,
        ContentUsage.LABEL_ONLY: 1,
        ContentUsage.FULL_TEXT: 2,
    }[record.content_usage]
    return (
        usage_rank,
        int(bool(record.definition)),
        int(bool(record.example)),
        record.record_id,
    )


def _deduplicate(
    records: Iterable[NormalizedSourceRecord],
) -> list[NormalizedSourceRecord]:
    catalog: dict[tuple[str, PartOfSpeech], NormalizedSourceRecord] = {}
    for record in records:
        if not record.word:
            continue
        key = _identity(record)
        existing = catalog.get(key)
        if existing is None or _preference(record) > _preference(existing):
            catalog[key] = record
    return sorted(
        catalog.values(),
        key=lambda record: (
            record.declared_topic,
            record.word or "",
            record.part_of_speech.value,
            record.record_id,
        ),
    )


def _take_cyclic_unique(
    records: list[NormalizedSourceRecord],
    *,
    start: int,
    count: int,
) -> tuple[NormalizedSourceRecord, ...]:
    selected: list[NormalizedSourceRecord] = []
    seen: set[tuple[str, PartOfSpeech]] = set()
    for offset in range(len(records)):
        record = records[(start + offset) % len(records)]
        identity = _identity(record)
        if identity in seen:
            continue
        selected.append(record)
        seen.add(identity)
        if len(selected) == count:
            break
    return tuple(selected)


def plan_curriculum(
    records: list[NormalizedSourceRecord],
    request: GenerationRequest,
) -> CurriculumPlan:
    """Create stable topic units and lesson vocabulary allocations."""

    selected_levels = set(request.levels)
    rejected_low_confidence = sum(
        1
        for record in records
        if record.word
        and record.declared_cefr in selected_levels
        and record.classification_confidence < request.confidence_threshold
    )
    eligible = [
        record
        for record in records
        if record.word
        and record.declared_cefr in selected_levels
        and record.classification_confidence >= request.confidence_threshold
    ]
    catalog = _deduplicate(eligible)
    courses: list[PlannedCourse] = []

    for level in sorted(request.levels, key=CEFR_LEVEL_ORDER.__getitem__):
        level_records = [
            record for record in catalog if record.declared_cefr == level
        ]
        if len(level_records) < request.words_per_lesson:
            raise InsufficientVocabularyError(
                f"{level.value} has {len(level_records)} usable vocabulary records; "
                f"{request.words_per_lesson} are required"
            )

        requested_topics = [
            _topic_slug(topic)
            for topic in request.topic_focus
            if topic.strip()
        ]
        available_topics = sorted(
            {record.declared_topic for record in level_records}
        )
        topics = list(dict.fromkeys(requested_topics or available_topics or ["general"]))

        units: list[PlannedUnit] = []
        lesson_cursor = 0
        for unit_index in range(request.units_per_course):
            topic = topics[unit_index % len(topics)]
            topic_records = [
                record for record in level_records if record.declared_topic == topic
            ]
            other_records = [
                record for record in level_records if record.declared_topic != topic
            ]
            pool = [*topic_records, *other_records]
            lessons: list[PlannedLesson] = []
            for lesson_index in range(request.lessons_per_unit):
                vocabulary = _take_cyclic_unique(
                    pool,
                    start=lesson_cursor * request.words_per_lesson,
                    count=request.words_per_lesson,
                )
                lessons.append(
                    PlannedLesson(
                        title=f"{_title(topic)} {lesson_index + 1}",
                        order_index=lesson_index,
                        level=level,
                        topic=topic,
                        vocabulary=vocabulary,
                    )
                )
                lesson_cursor += 1

            unit_suffix = (
                f" {unit_index // len(topics) + 1}"
                if request.units_per_course > len(topics)
                else ""
            )
            units.append(
                PlannedUnit(
                    title=f"{_title(topic)}{unit_suffix}",
                    order_index=unit_index,
                    topic=topic,
                    lessons=tuple(lessons),
                )
            )

        course_title = (
            f"{request.title_focus.strip()} {level.value}"
            if request.title_focus and request.title_focus.strip()
            else f"English {level.value} Foundations"
        )
        courses.append(
            PlannedCourse(
                title=course_title,
                description=(
                    f"An original {level.value} English course organized by topic."
                ),
                level=level,
                units=tuple(units),
            )
        )

    return CurriculumPlan(
        courses=tuple(courses),
        catalog_size=len(catalog),
        rejected_low_confidence=rejected_low_confidence,
    )
