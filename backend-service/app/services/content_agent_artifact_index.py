"""Typed traversal index for raw content-agent artifacts.

The validation service receives raw dictionaries from jobs, uploads, and AI
responses.  This module centralizes the defensive walk over the nested
course/unit/lesson tree so validation rules can work with dict-only nodes.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class StructuralIssue:
    code: str
    path: str
    message: str


@dataclass(frozen=True)
class ObjectNode:
    path: str
    data: dict[str, Any]


@dataclass(frozen=True)
class LessonNode:
    path: str
    data: dict[str, Any]
    vocabulary: tuple[ObjectNode, ...]
    exercises: tuple[ObjectNode, ...]


@dataclass(frozen=True)
class UnitNode:
    path: str
    data: dict[str, Any]
    lessons: tuple[LessonNode, ...]


@dataclass(frozen=True)
class CourseNode:
    path: str
    data: dict[str, Any]
    units: tuple[UnitNode, ...]


@dataclass(frozen=True)
class ArtifactIndex:
    courses: tuple[CourseNode, ...]
    units: tuple[UnitNode, ...]
    lessons: tuple[LessonNode, ...]
    vocabulary: tuple[ObjectNode, ...]
    exercises: tuple[ObjectNode, ...]
    structural_errors: tuple[StructuralIssue, ...] = field(default_factory=tuple)


def _add_issue(
    issues: list[StructuralIssue], code: str, path: str, message: str
) -> None:
    issues.append(StructuralIssue(code=code, path=path, message=message))


def _list_field(
    owner: dict[str, Any],
    field_name: str,
    path: str,
    issues: list[StructuralIssue],
    type_code: str,
) -> list[Any]:
    value = owner.get(field_name)
    if value is None:
        return []
    if not isinstance(value, list):
        _add_issue(issues, type_code, path, f"{field_name} must be a list")
        return []
    return value


def _object_node(
    value: Any,
    path: str,
    issues: list[StructuralIssue],
    code: str,
    label: str,
) -> dict[str, Any] | None:
    if isinstance(value, dict):
        return value
    _add_issue(issues, code, path, f"{label} must be an object")
    return None


def build_artifact_index(artifact: dict[str, Any]) -> ArtifactIndex:
    issues: list[StructuralIssue] = []
    courses_raw = artifact.get("courses")
    if courses_raw is None:
        courses_raw = []
    elif not isinstance(courses_raw, list):
        _add_issue(issues, "COURSES_TYPE", "courses", "courses must be a list")
        courses_raw = []

    courses: list[CourseNode] = []
    all_units: list[UnitNode] = []
    all_lessons: list[LessonNode] = []
    all_vocabulary: list[ObjectNode] = []
    all_exercises: list[ObjectNode] = []

    for ci, course_value in enumerate(courses_raw):
        course_path = f"courses[{ci}]"
        course = _object_node(
            course_value,
            course_path,
            issues,
            "COURSE_ENTRY_TYPE",
            "course entry",
        )
        if course is None:
            continue

        units_raw = _list_field(
            course,
            "units",
            f"{course_path}.units",
            issues,
            "UNITS_TYPE",
        )
        if not units_raw:
            _add_issue(
                issues,
                "NO_UNITS",
                f"{course_path}.units",
                "course must contain at least one unit",
            )

        unit_nodes: list[UnitNode] = []
        for ui, unit_value in enumerate(units_raw):
            unit_path = f"{course_path}.units[{ui}]"
            unit = _object_node(
                unit_value,
                unit_path,
                issues,
                "UNIT_ENTRY_TYPE",
                "unit entry",
            )
            if unit is None:
                continue

            lessons_raw = _list_field(
                unit,
                "lessons",
                f"{unit_path}.lessons",
                issues,
                "LESSONS_TYPE",
            )
            if not lessons_raw:
                _add_issue(
                    issues,
                    "NO_LESSONS",
                    f"{unit_path}.lessons",
                    "unit must contain at least one lesson",
                )

            lesson_nodes: list[LessonNode] = []
            for li, lesson_value in enumerate(lessons_raw):
                lesson_path = f"{unit_path}.lessons[{li}]"
                lesson = _object_node(
                    lesson_value,
                    lesson_path,
                    issues,
                    "LESSON_ENTRY_TYPE",
                    "lesson entry",
                )
                if lesson is None:
                    continue

                vocabulary_raw = _list_field(
                    lesson,
                    "vocabulary",
                    f"{lesson_path}.vocabulary",
                    issues,
                    "VOCABULARY_TYPE",
                )
                vocabulary_nodes: list[ObjectNode] = []
                for vi, vocab_value in enumerate(vocabulary_raw):
                    vocab_path = f"{lesson_path}.vocabulary[{vi}]"
                    vocab = _object_node(
                        vocab_value,
                        vocab_path,
                        issues,
                        "VOCABULARY_ENTRY_TYPE",
                        "vocabulary entry",
                    )
                    if vocab is not None:
                        vocabulary_nodes.append(ObjectNode(vocab_path, vocab))

                exercises_raw = _list_field(
                    lesson,
                    "exercises",
                    f"{lesson_path}.exercises",
                    issues,
                    "EXERCISES_TYPE",
                )
                exercise_nodes: list[ObjectNode] = []
                for ei, exercise_value in enumerate(exercises_raw):
                    exercise_path = f"{lesson_path}.exercises[{ei}]"
                    exercise = _object_node(
                        exercise_value,
                        exercise_path,
                        issues,
                        "EXERCISE_ENTRY_TYPE",
                        "exercise entry",
                    )
                    if exercise is not None:
                        exercise_nodes.append(ObjectNode(exercise_path, exercise))

                lesson_node = LessonNode(
                    path=lesson_path,
                    data=lesson,
                    vocabulary=tuple(vocabulary_nodes),
                    exercises=tuple(exercise_nodes),
                )
                lesson_nodes.append(lesson_node)
                all_vocabulary.extend(vocabulary_nodes)
                all_exercises.extend(exercise_nodes)

            unit_node = UnitNode(
                path=unit_path,
                data=unit,
                lessons=tuple(lesson_nodes),
            )
            unit_nodes.append(unit_node)
            all_lessons.extend(lesson_nodes)

        course_node = CourseNode(
            path=course_path,
            data=course,
            units=tuple(unit_nodes),
        )
        courses.append(course_node)
        all_units.extend(unit_nodes)

    return ArtifactIndex(
        courses=tuple(courses),
        units=tuple(all_units),
        lessons=tuple(all_lessons),
        vocabulary=tuple(all_vocabulary),
        exercises=tuple(all_exercises),
        structural_errors=tuple(issues),
    )
