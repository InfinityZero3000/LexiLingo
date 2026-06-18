"""Pure artifact/database-boundary validator for CEFR content-agent output.

All functions are stateless and do not touch the database.  The only input
is the raw artifact dict (as stored on the job row); the only output is a
:class:`ValidationReport`.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
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
_SHA256_PATTERN: re.Pattern[str] = re.compile(r"^[a-f0-9]{64}$")
_MANIFEST_REQUIRED_FIELDS: frozenset[str] = frozenset(
    {
        "snapshot_id",
        "source_name",
        "source_version",
        "official_url",
        "license_id",
        "license_url",
        "attribution_text",
        "retrieved_at",
        "raw_checksum",
        "normalized_sha256",
        "normalized_bytes",
        "record_checksum_root",
        "adapter_version",
        "record_count",
    }
)
_PINNED_PROVENANCE_FIELDS: tuple[str, ...] = (
    "source_version",
    "license_id",
    "license_url",
    "attribution_text",
    "raw_checksum",
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


def _coerce_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


@lru_cache(maxsize=1)
def _exercise_type_mapping() -> dict[str, str]:
    contract_path = (
        Path(__file__).resolve().parents[3]
        / "contracts"
        / "content-agent"
        / "exercise-types-v1.json"
    )
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    return dict(contract["ui_type_to_type"])


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


def _check_manifest_coverage(
    artifact: dict[str, Any],
    report: ValidationReport,
    pinned_snapshots: list[dict[str, Any]],
    admin_upload: dict[str, Any] | None,
) -> None:
    manifest: list = artifact.get("source_manifest") or []
    if not manifest:
        _blocking(
            report,
            "MANIFEST_EMPTY",
            "source_manifest",
            "source_manifest must contain at least one entry",
        )
        return
    manifest_by_source: dict[str, dict[str, Any]] = {}
    for idx, entry in enumerate(manifest):
        path = f"source_manifest[{idx}]"
        if not isinstance(entry, dict):
            _blocking(
                report,
                "MANIFEST_ENTRY_TYPE",
                path,
                "each source_manifest entry must be an object",
            )
            continue
        missing = sorted(
            field_name
            for field_name in _MANIFEST_REQUIRED_FIELDS
            if entry.get(field_name) in (None, "")
        )
        if missing:
            _blocking(
                report,
                "MANIFEST_FIELDS_MISSING",
                path,
                f"manifest entry is missing required fields: {', '.join(missing)}",
            )
        source_name = str(entry.get("source_name") or "")
        if source_name in manifest_by_source:
            _blocking(
                report,
                "MANIFEST_SOURCE_DUPLICATE",
                f"{path}.source_name",
                f"source_name '{source_name}' appears more than once",
            )
        elif source_name:
            manifest_by_source[source_name] = entry
        for url_field in ("official_url", "license_url"):
            if not _is_valid_url(str(entry.get(url_field) or "")):
                _blocking(
                    report,
                    "MANIFEST_URL_INVALID",
                    f"{path}.{url_field}",
                    f"{url_field} must be a valid http/https URL",
                )
        for checksum_field in (
            "raw_checksum",
            "normalized_sha256",
            "record_checksum_root",
        ):
            if not _SHA256_PATTERN.fullmatch(str(entry.get(checksum_field) or "")):
                _blocking(
                    report,
                    "MANIFEST_CHECKSUM_INVALID",
                    f"{path}.{checksum_field}",
                    f"{checksum_field} must be a lowercase SHA-256 digest",
                )
        if not isinstance(entry.get("normalized_bytes"), int) or entry.get(
            "normalized_bytes", 0
        ) < 1:
            _blocking(
                report,
                "MANIFEST_NORMALIZED_BYTES_INVALID",
                f"{path}.normalized_bytes",
                "normalized_bytes must be a positive integer",
            )
        if not isinstance(entry.get("adapter_version"), int) or entry.get(
            "adapter_version", 0
        ) < 1:
            _blocking(
                report,
                "MANIFEST_ADAPTER_VERSION_INVALID",
                f"{path}.adapter_version",
                "adapter_version must be a positive integer",
            )
        if not isinstance(entry.get("record_count"), int) or entry.get(
            "record_count", 0
        ) < 1:
            _blocking(
                report,
                "MANIFEST_RECORD_COUNT_INVALID",
                f"{path}.record_count",
                "record_count must be a positive integer",
            )

    for pin in pinned_snapshots:
        source_name = str(pin.get("source_name") or pin.get("source_id") or "")
        entry = manifest_by_source.get(source_name)
        if entry is None:
            _blocking(
                report,
                "PINNED_SNAPSHOT_MISSING",
                "source_manifest",
                f"pinned source '{source_name}' is absent from the artifact manifest",
            )
            continue
        for field_name in (
            "snapshot_id",
            "source_version",
            "official_url",
            "license_id",
            "license_url",
            "attribution_text",
            "retrieved_at",
            "raw_checksum",
            "normalized_sha256",
            "normalized_bytes",
            "record_checksum_root",
            "adapter_version",
            "record_count",
        ):
            if str(entry.get(field_name)) != str(pin.get(field_name)):
                _blocking(
                    report,
                    "PINNED_SNAPSHOT_MISMATCH",
                    f"source_manifest[{source_name}].{field_name}",
                    f"{field_name} does not match the snapshot pinned to the job",
                )

    pinned_sources = {
        str(pin.get("source_name") or pin.get("source_id"))
        for pin in pinned_snapshots
    }
    allowed_manifest_sources = set(pinned_sources)
    if admin_upload is not None:
        allowed_manifest_sources.add("admin_upload")
    for source_name in manifest_by_source:
        if source_name not in allowed_manifest_sources:
            _blocking(
                report,
                "MANIFEST_SOURCE_NOT_PINNED",
                f"source_manifest[{source_name}].source_name",
                f"source '{source_name}' was not pinned or attested for this job",
            )

    admin_manifest = manifest_by_source.get("admin_upload")
    if admin_manifest is not None:
        if admin_upload is None:
            _blocking(
                report,
                "ADMIN_UPLOAD_NOT_ATTESTED",
                "source_manifest[admin_upload]",
                "admin_upload content requires a surviving attested upload",
            )
        else:
            expected_checksum = str(admin_upload.get("checksum") or "")
            expected_rows = int(admin_upload.get("row_count") or 0)
            if str(admin_manifest.get("raw_checksum")) != expected_checksum:
                _blocking(
                    report,
                    "ADMIN_UPLOAD_CHECKSUM_MISMATCH",
                    "source_manifest[admin_upload].raw_checksum",
                    "admin_upload raw_checksum must match the attested upload",
                )
            if _coerce_int(admin_manifest.get("record_count")) != expected_rows:
                _blocking(
                    report,
                    "ADMIN_UPLOAD_ROW_COUNT_MISMATCH",
                    "source_manifest[admin_upload].record_count",
                    "admin_upload record_count must match the attested upload",
                )
            if str(admin_manifest.get("license_id")) != "LicenseRef-Admin-Owned":
                _blocking(
                    report,
                    "ADMIN_UPLOAD_LICENSE_INVALID",
                    "source_manifest[admin_upload].license_id",
                    "admin_upload content must use the admin-owned license ref",
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


def _check_provenance(
    artifact: dict[str, Any],
    report: ValidationReport,
    pinned_snapshots: list[dict[str, Any]],
) -> None:
    """All imported vocabulary must be traceable to the job's exact snapshot."""
    manifest_by_source = {
        str(entry.get("source_name")): entry
        for entry in artifact.get("source_manifest") or []
        if isinstance(entry, dict) and entry.get("source_name")
    }
    pinned_by_source = {
        str(pin.get("source_name") or pin.get("source_id")): pin
        for pin in pinned_snapshots
    }
    courses = artifact.get("courses") or []
    for ci, course in enumerate(courses):
        for ui, unit in enumerate(course.get("units") or []):
            for li, lesson in enumerate(unit.get("lessons") or []):
                for vi, vocab in enumerate(lesson.get("vocabulary") or []):
                    base = (
                        f"courses[{ci}].units[{ui}].lessons[{li}]"
                        f".vocabulary[{vi}]"
                    )
                    mode = vocab.get("license_mode", "")
                    if mode not in _LICENSE_MODES:
                        _blocking(
                            report,
                            "INVALID_LICENSE_MODE",
                            f"{base}.license_mode",
                            f"license_mode '{mode}' is not storable",
                        )
                    source_name = str(vocab.get("source_name") or "")
                    if source_name == "generated":
                        if mode != "generated":
                            _blocking(
                                report,
                                "GENERATED_LICENSE_MODE_INVALID",
                                f"{base}.license_mode",
                                "generated vocabulary must use license_mode 'generated'",
                            )
                        for field_name in (
                            "source_url",
                            "source_checksum",
                            "source_version",
                            "source_record_id",
                            "license_id",
                            "license_url",
                            "attribution_text",
                            "raw_checksum",
                            "record_checksum",
                            "lineage",
                            "content_usage",
                        ):
                            if vocab.get(field_name) not in (None, "", {}):
                                _blocking(
                                    report,
                                    "GENERATED_PROVENANCE_PRESENT",
                                    f"{base}.{field_name}",
                                    "generated vocabulary must not carry imported "
                                    "source provenance",
                                )
                        continue
                    manifest = manifest_by_source.get(source_name)
                    if manifest is None:
                        _blocking(
                            report,
                            "VOCAB_SOURCE_NOT_IN_MANIFEST",
                            f"{base}.source_name",
                            f"source '{source_name}' is absent from source_manifest",
                        )
                        continue
                    pin = pinned_by_source.get(source_name)
                    if source_name == "admin_upload":
                        required_fields = (
                            "source_record_id",
                            "record_checksum",
                            "lineage",
                            "content_usage",
                            "source_version",
                            "license_id",
                            "license_url",
                            "attribution_text",
                            "raw_checksum",
                        )
                        for field_name in required_fields:
                            if vocab.get(field_name) in (None, "", {}):
                                _blocking(
                                    report,
                                    "VOCAB_PROVENANCE_MISSING",
                                    f"{base}.{field_name}",
                                    f"{field_name} is required for admin upload content",
                                )
                        if mode != "admin_owned":
                            _blocking(
                                report,
                                "ADMIN_UPLOAD_LICENSE_MODE_INVALID",
                                f"{base}.license_mode",
                                "admin_upload vocabulary must use admin_owned mode",
                            )
                        for field_name in (
                            "source_version",
                            "license_id",
                            "license_url",
                            "attribution_text",
                            "raw_checksum",
                        ):
                            if str(vocab.get(field_name)) != str(
                                manifest.get(field_name)
                            ):
                                _blocking(
                                    report,
                                    "VOCAB_PROVENANCE_MISMATCH",
                                    f"{base}.{field_name}",
                                    f"{field_name} does not match the admin upload manifest",
                                )
                        if not _SHA256_PATTERN.fullmatch(
                            str(vocab.get("record_checksum") or "")
                        ):
                            _blocking(
                                report,
                                "VOCAB_RECORD_CHECKSUM_INVALID",
                                f"{base}.record_checksum",
                                "record_checksum must be a lowercase SHA-256 digest",
                            )
                        lineage = vocab.get("lineage")
                        if not isinstance(lineage, dict) or not {
                            "adapter",
                            "adapter_version",
                            "raw_path",
                        }.issubset(lineage):
                            _blocking(
                                report,
                                "VOCAB_LINEAGE_INVALID",
                                f"{base}.lineage",
                                "lineage must identify adapter, adapter_version, and raw_path",
                            )
                        continue
                    if pin is None:
                        _blocking(
                            report,
                            "VOCAB_SOURCE_NOT_PINNED",
                            f"{base}.source_name",
                            f"dataset source '{source_name}' was not pinned to the job",
                        )
                        continue
                    required_fields = (
                        "source_url",
                        "source_record_id",
                        "record_checksum",
                        "lineage",
                        "content_usage",
                        *_PINNED_PROVENANCE_FIELDS,
                    )
                    for field_name in required_fields:
                        if vocab.get(field_name) in (None, "", {}):
                            _blocking(
                                report,
                                "VOCAB_PROVENANCE_MISSING",
                                f"{base}.{field_name}",
                                f"{field_name} is required for pinned dataset content",
                            )
                    if not _is_valid_url(str(vocab.get("source_url") or "")):
                        _blocking(
                            report,
                            "INVALID_SOURCE_URL",
                            f"{base}.source_url",
                            "source_url must be a valid http/https URL",
                        )
                    if not _SHA256_PATTERN.fullmatch(
                        str(vocab.get("record_checksum") or "")
                    ):
                        _blocking(
                            report,
                            "VOCAB_RECORD_CHECKSUM_INVALID",
                            f"{base}.record_checksum",
                            "record_checksum must be a lowercase SHA-256 digest",
                        )
                    lineage = vocab.get("lineage")
                    if not isinstance(lineage, dict) or not {
                        "adapter",
                        "adapter_version",
                        "raw_path",
                    }.issubset(lineage):
                        _blocking(
                            report,
                            "VOCAB_LINEAGE_INVALID",
                            f"{base}.lineage",
                            "lineage must identify adapter, adapter_version, and raw_path",
                        )
                    for field_name in _PINNED_PROVENANCE_FIELDS:
                        if str(vocab.get(field_name)) != str(pin.get(field_name)):
                            _blocking(
                                report,
                                "VOCAB_PROVENANCE_MISMATCH",
                                f"{base}.{field_name}",
                                f"{field_name} does not match the pinned snapshot",
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
                    elif _exercise_type_mapping().get(ui_type) != etype:
                        _blocking(
                            report,
                            "EXERCISE_UI_TYPE_MISMATCH",
                            f"{base}.ui_type",
                            f"ui_type '{ui_type}' is not valid for exercise type '{etype}'",
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


def validate_artifact(
    artifact: dict[str, Any],
    *,
    pinned_snapshots: list[dict[str, Any]] | None = None,
    admin_upload: dict[str, Any] | None = None,
) -> ValidationReport:
    """Run all validation gates against *artifact* and return a :class:`ValidationReport`.

    This function is pure — it never reads from or writes to the database.
    Gates run in this order so that blocking errors about fundamental structure
    appear before finer-grained content errors.
    """
    report = ValidationReport()
    pins = pinned_snapshots or []

    _check_schema_version(artifact, report)
    _check_manifest_coverage(artifact, report, pins, admin_upload)
    _check_courses_present(artifact, report)
    _check_course_levels(artifact, report)
    _check_provenance(artifact, report, pins)
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
