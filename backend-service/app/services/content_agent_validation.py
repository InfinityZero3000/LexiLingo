"""Pure artifact/database-boundary validator for CEFR content-agent output.

All functions are stateless and do not touch the database.  The only input
is the raw artifact dict (as stored on the job row); the only output is a
:class:`ValidationReport`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

# ---------------------------------------------------------------------------
# Valid enum sets (mirrors the Pydantic schema without importing it to keep
# this module importable before the ORM is initialised)
# ---------------------------------------------------------------------------

_CEFR_LEVELS: frozenset[str] = frozenset({"A1", "A2", "B1", "B2", "C1", "C2"})
_POS_VALUES: frozenset[str] = frozenset(
    {
        "noun",
        "verb",
        "adjective",
        "adverb",
        "pronoun",
        "preposition",
        "conjunction",
        "interjection",
        "phrase",
    }
)
_EXERCISE_TYPES: frozenset[str] = frozenset(
    {"multiple_choice", "true_false", "fill_blank", "translate", "matching", "reorder"}
)
_LICENSE_MODES: frozenset[str] = frozenset(
    {"generated", "approved_dataset", "admin_owned", "public_domain_verified"}
)
_URL_PATTERN: re.Pattern[str] = re.compile(
    r"^https?://[^\s/$.?#].[^\s]*$", re.IGNORECASE
)

# Minimum and maximum definition character counts
_DEF_MIN_CHARS = 10
_DEF_MAX_CHARS = 2000


@dataclass(frozen=True)
class ValidationIssue:
    code: str
    path: str
    message: str


@dataclass
class ValidationReport:
    blocking_errors: list[ValidationIssue] = field(default_factory=list)
    warnings: list[ValidationIssue] = field(default_factory=list)
    metrics: dict[str, Any] = field(default_factory=dict)

    @property
    def is_blocking(self) -> bool:
        return bool(self.blocking_errors)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _blocking(
    report: ValidationReport, code: str, path: str, message: str
) -> None:
    report.blocking_errors.append(ValidationIssue(code=code, path=path, message=message))


def _warn(report: ValidationReport, code: str, path: str, message: str) -> None:
    report.warnings.append(ValidationIssue(code=code, path=path, message=message))


def _is_valid_url(value: str | None) -> bool:
    return bool(value and _URL_PATTERN.match(value))


# ---------------------------------------------------------------------------
# Gate implementations
# ---------------------------------------------------------------------------


def _check_schema_version(artifact: dict[str, Any], report: ValidationReport) -> None:
    version = artifact.get("schema_version")
    if version != 2:
        _blocking(
            report,
            "SCHEMA_VERSION",
            "schema_version",
            f"schema_version must be 2, got {version!r}",
        )


def _check_manifest_coverage(artifact: dict[str, Any], report: ValidationReport) -> None:
    manifest: list = artifact.get("source_manifest") or []
    if not manifest:
        _blocking(
            report,
            "MANIFEST_EMPTY",
            "source_manifest",
            "source_manifest must contain at least one entry",
        )
        return
    for idx, entry in enumerate(manifest):
        if not isinstance(entry, dict):
            _blocking(
                report,
                "MANIFEST_ENTRY_TYPE",
                f"source_manifest[{idx}]",
                "each source_manifest entry must be an object",
            )


def _check_courses_present(artifact: dict[str, Any], report: ValidationReport) -> None:
    courses = artifact.get("courses") or []
    if not courses:
        _blocking(
            report,
            "NO_COURSES",
            "courses",
            "artifact must contain at least one course",
        )


def _check_provenance(artifact: dict[str, Any], report: ValidationReport) -> None:
    """All vocabulary must use a storable license_mode."""
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for vi, vocab in enumerate(lesson.get("vocabulary") or []):
                    mode = vocab.get("license_mode", "")
                    if mode not in _LICENSE_MODES:
                        _blocking(
                            report,
                            "INVALID_LICENSE_MODE",
                            f"courses[{ci}].units[{ui}].lessons[{li}].vocabulary[{vi}].license_mode",
                            f"license_mode '{mode}' is not storable",
                        )


def _check_course_levels(artifact: dict[str, Any], report: ValidationReport) -> None:
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        level = course.get("level", "")
        if level not in _CEFR_LEVELS:
            _blocking(
                report,
                "INVALID_COURSE_LEVEL",
                f"courses[{ci}].level",
                f"course level '{level}' is not a valid CEFR level",
            )


def _check_unique_lesson_orders(
    artifact: dict[str, Any], report: ValidationReport
) -> None:
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            orders = [
                lesson.get("order_index")
                for lesson in (unit.get("lessons") or [])
            ]
            if len(orders) != len(set(orders)):
                _blocking(
                    report,
                    "DUPLICATE_LESSON_ORDER",
                    f"courses[{ci}].units[{ui}].lessons[*].order_index",
                    "lesson order_index values must be unique within a unit",
                )


def _check_definition_length(
    artifact: dict[str, Any], report: ValidationReport
) -> None:
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for vi, vocab in enumerate(lesson.get("vocabulary") or []):
                    definition = str(vocab.get("definition") or "")
                    path = f"courses[{ci}].units[{ui}].lessons[{li}].vocabulary[{vi}].definition"
                    if len(definition) < _DEF_MIN_CHARS:
                        _blocking(
                            report,
                            "DEFINITION_TOO_SHORT",
                            path,
                            f"definition must be at least {_DEF_MIN_CHARS} characters",
                        )
                    elif len(definition) > _DEF_MAX_CHARS:
                        _blocking(
                            report,
                            "DEFINITION_TOO_LONG",
                            path,
                            f"definition must not exceed {_DEF_MAX_CHARS} characters",
                        )


def _check_pos_enum(artifact: dict[str, Any], report: ValidationReport) -> None:
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for vi, vocab in enumerate(lesson.get("vocabulary") or []):
                    pos = vocab.get("part_of_speech", "")
                    if pos not in _POS_VALUES:
                        _blocking(
                            report,
                            "INVALID_POS",
                            f"courses[{ci}].units[{ui}].lessons[{li}].vocabulary[{vi}].part_of_speech",
                            f"part_of_speech '{pos}' is not a recognised value",
                        )


def _check_cefr_enum(artifact: dict[str, Any], report: ValidationReport) -> None:
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for vi, vocab in enumerate(lesson.get("vocabulary") or []):
                    level = vocab.get("difficulty_level", "")
                    if level not in _CEFR_LEVELS:
                        _blocking(
                            report,
                            "INVALID_VOCAB_CEFR",
                            f"courses[{ci}].units[{ui}].lessons[{li}].vocabulary[{vi}].difficulty_level",
                            f"difficulty_level '{level}' is not a valid CEFR level",
                        )


def _check_translation_shape(
    artifact: dict[str, Any], report: ValidationReport
) -> None:
    """Warn when translation_vi is non-null but suspiciously short."""
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for vi, vocab in enumerate(lesson.get("vocabulary") or []):
                    tv = vocab.get("translation_vi")
                    if tv is not None and len(str(tv).strip()) < 1:
                        _warn(
                            report,
                            "EMPTY_TRANSLATION_VI",
                            f"courses[{ci}].units[{ui}].lessons[{li}].vocabulary[{vi}].translation_vi",
                            "translation_vi is present but empty",
                        )


def _check_urls(artifact: dict[str, Any], report: ValidationReport) -> None:
    """Blocking: any non-null source_url must be a valid HTTP/S URL."""
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for vi, vocab in enumerate(lesson.get("vocabulary") or []):
                    url = vocab.get("source_url")
                    if url is not None and not _is_valid_url(url):
                        _blocking(
                            report,
                            "INVALID_SOURCE_URL",
                            f"courses[{ci}].units[{ui}].lessons[{li}].vocabulary[{vi}].source_url",
                            "source_url must be a valid http/https URL when provided",
                        )
                for ei, exercise in enumerate(lesson.get("exercises") or []):
                    for url_field in ("audio_url", "image_url"):
                        url = exercise.get(url_field)
                        if url is not None and not _is_valid_url(url):
                            _blocking(
                                report,
                                "INVALID_EXERCISE_URL",
                                f"courses[{ci}].units[{ui}].lessons[{li}].exercises[{ei}].{url_field}",
                                f"{url_field} must be a valid http/https URL when provided",
                            )


def _check_exercise_ids(artifact: dict[str, Any], report: ValidationReport) -> None:
    """Exercise IDs must be unique within the whole artifact."""
    seen: set[str] = set()
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for ei, exercise in enumerate(lesson.get("exercises") or []):
                    eid = exercise.get("id") or ""
                    if not eid:
                        _blocking(
                            report,
                            "EXERCISE_MISSING_ID",
                            f"courses[{ci}].units[{ui}].lessons[{li}].exercises[{ei}].id",
                            "exercise id must not be empty",
                        )
                    elif eid in seen:
                        _blocking(
                            report,
                            "DUPLICATE_EXERCISE_ID",
                            f"courses[{ci}].units[{ui}].lessons[{li}].exercises[{ei}].id",
                            f"exercise id '{eid}' is duplicated across the artifact",
                        )
                    else:
                        seen.add(eid)


def _check_exercise_type_ui_type(
    artifact: dict[str, Any], report: ValidationReport
) -> None:
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for ei, exercise in enumerate(lesson.get("exercises") or []):
                    etype = exercise.get("type", "")
                    ui_type = exercise.get("ui_type", "")
                    base = f"courses[{ci}].units[{ui}].lessons[{li}].exercises[{ei}]"
                    if etype not in _EXERCISE_TYPES:
                        _blocking(
                            report,
                            "INVALID_EXERCISE_TYPE",
                            f"{base}.type",
                            f"exercise type '{etype}' is not recognised",
                        )
                    if not ui_type:
                        _blocking(
                            report,
                            "MISSING_UI_TYPE",
                            f"{base}.ui_type",
                            "ui_type must not be empty",
                        )


def _check_options(artifact: dict[str, Any], report: ValidationReport) -> None:
    """multiple_choice exercises must have at least 2 options."""
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for ei, exercise in enumerate(lesson.get("exercises") or []):
                    if exercise.get("type") == "multiple_choice":
                        options = exercise.get("options") or []
                        if len(options) < 2:
                            _blocking(
                                report,
                                "MC_INSUFFICIENT_OPTIONS",
                                f"courses[{ci}].units[{ui}].lessons[{li}].exercises[{ei}].options",
                                "multiple_choice exercise must have at least 2 options",
                            )


def _check_speaking_listening_text(
    artifact: dict[str, Any], report: ValidationReport
) -> None:
    """Exercises with audio_url must have a non-empty question for listening."""
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for ei, exercise in enumerate(lesson.get("exercises") or []):
                    audio_url = exercise.get("audio_url")
                    question = str(exercise.get("question") or "").strip()
                    if audio_url and not question:
                        _blocking(
                            report,
                            "MISSING_AUDIO_QUESTION",
                            f"courses[{ci}].units[{ui}].lessons[{li}].exercises[{ei}].question",
                            "exercises with audio_url must have a non-empty question",
                        )


def _check_counts(artifact: dict[str, Any], report: ValidationReport) -> None:
    """Warn when lesson vocabulary or exercise counts look off."""
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                vocab_count = len(lesson.get("vocabulary") or [])
                ex_count = len(lesson.get("exercises") or [])
                path_base = f"courses[{ci}].units[{ui}].lessons[{li}]"
                if vocab_count == 0:
                    _blocking(
                        report,
                        "NO_VOCABULARY",
                        f"{path_base}.vocabulary",
                        "lesson must have at least one vocabulary item",
                    )
                if ex_count == 0:
                    _blocking(
                        report,
                        "NO_EXERCISES",
                        f"{path_base}.exercises",
                        "lesson must have at least one exercise",
                    )


def _collect_metrics(artifact: dict[str, Any]) -> dict[str, Any]:
    courses = artifact.get("courses") or []
    total_units = 0
    total_lessons = 0
    total_vocab = 0
    total_exercises = 0
    for course in courses:
        for unit in course.get("units") or []:
            total_units += 1
            for lesson in unit.get("lessons") or []:
                total_lessons += 1
                total_vocab += len(lesson.get("vocabulary") or [])
                total_exercises += len(lesson.get("exercises") or [])
    return {
        "course_count": len(courses),
        "unit_count": total_units,
        "lesson_count": total_lessons,
        "vocabulary_count": total_vocab,
        "exercise_count": total_exercises,
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def validate_artifact(artifact: dict[str, Any]) -> ValidationReport:
    """Run all validation gates against *artifact* and return a :class:`ValidationReport`.

    This function is pure — it never reads from or writes to the database.
    Gates run in this order so that blocking errors about fundamental structure
    appear before finer-grained content errors.
    """
    report = ValidationReport()

    _check_schema_version(artifact, report)
    _check_manifest_coverage(artifact, report)
    _check_courses_present(artifact, report)
    _check_course_levels(artifact, report)
    _check_provenance(artifact, report)
    _check_unique_lesson_orders(artifact, report)
    _check_definition_length(artifact, report)
    _check_pos_enum(artifact, report)
    _check_cefr_enum(artifact, report)
    _check_translation_shape(artifact, report)
    _check_urls(artifact, report)
    _check_exercise_ids(artifact, report)
    _check_exercise_type_ui_type(artifact, report)
    _check_options(artifact, report)
    _check_speaking_listening_text(artifact, report)
    _check_counts(artifact, report)

    report.metrics = _collect_metrics(artifact)
    return report
