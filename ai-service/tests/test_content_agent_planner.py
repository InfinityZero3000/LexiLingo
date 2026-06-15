import pytest
from pydantic import ValidationError

from api.models.content_agent import GenerationRequest
from api.services.content_agent.adapters import normalize_source_records
from api.services.content_agent.planner import (
    InsufficientVocabularyError,
    plan_curriculum,
)


def _records(level: str, count: int, *, confidence: float = 1.0):
    return normalize_source_records(
        [
            {
                "record_id": f"upload:{level}:{index}",
                "word": f"{level.lower()}word{index:02d}",
                "part_of_speech": "noun",
                "declared_cefr": level,
                "declared_topic": "daily_life" if index % 2 == 0 else "travel",
                "classification_confidence": confidence,
            }
            for index in range(count)
        ],
        source_name="admin_upload",
    )


def test_planner_creates_one_course_per_selected_level_in_cefr_order():
    records = [*_records("A1", 12), *_records("B1", 12)]
    request = GenerationRequest(
        levels=["B1", "A1"],
        units_per_course=1,
        lessons_per_unit=1,
        words_per_lesson=10,
    )

    result = plan_curriculum(records, request)

    assert [course.level.value for course in result.courses] == ["A1", "B1"]
    assert all(len(course.units) == 1 for course in result.courses)
    assert all(len(course.units[0].lessons[0].vocabulary) == 10 for course in result.courses)


def test_planner_is_stable_and_reuses_catalog_items_without_lesson_duplicates():
    records = _records("A2", 10)
    request = GenerationRequest(
        levels=["A2"],
        units_per_course=1,
        lessons_per_unit=2,
        words_per_lesson=8,
    )

    first = plan_curriculum(records, request)
    second = plan_curriculum(list(reversed(records)), request)

    assert first == second
    lessons = first.courses[0].units[0].lessons
    lesson_keys = [
        [(item.word, item.part_of_speech) for item in lesson.vocabulary]
        for lesson in lessons
    ]
    assert all(len(keys) == len(set(keys)) == 8 for keys in lesson_keys)
    assert len(set(lesson_keys[0]) | set(lesson_keys[1])) == 10
    assert first.catalog_size == 10


def test_planner_rejects_low_confidence_records():
    records = [
        *_records("B2", 8, confidence=0.95),
        *_records("B2", 2, confidence=0.4),
    ]
    request = GenerationRequest(
        levels=["B2"],
        units_per_course=1,
        lessons_per_unit=1,
        words_per_lesson=8,
        confidence_threshold=0.7,
    )

    result = plan_curriculum(records, request)

    assert result.rejected_low_confidence == 2
    assert len(result.courses[0].units[0].lessons[0].vocabulary) == 8


def test_words_per_lesson_is_constrained_to_eight_through_twelve():
    with pytest.raises(ValidationError):
        GenerationRequest(levels=["A1"], words_per_lesson=7)
    with pytest.raises(ValidationError):
        GenerationRequest(levels=["A1"], words_per_lesson=13)


def test_planner_reports_insufficient_vocabulary():
    with pytest.raises(InsufficientVocabularyError):
        plan_curriculum(
            _records("C1", 7),
            GenerationRequest(
                levels=["C1"],
                units_per_course=1,
                lessons_per_unit=1,
                words_per_lesson=8,
            ),
        )
