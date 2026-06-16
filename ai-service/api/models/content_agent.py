"""Contracts for the compliance-first CEFR content agent."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Literal

from pydantic import (
    AliasChoices,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


class CEFRLevel(str, Enum):
    A1 = "A1"
    A2 = "A2"
    B1 = "B1"
    B2 = "B2"
    C1 = "C1"
    C2 = "C2"


CEFR_LEVEL_ORDER = {level: index for index, level in enumerate(CEFRLevel)}


class PartOfSpeech(str, Enum):
    NOUN = "noun"
    VERB = "verb"
    ADJECTIVE = "adjective"
    ADVERB = "adverb"
    PRONOUN = "pronoun"
    PREPOSITION = "preposition"
    CONJUNCTION = "conjunction"
    INTERJECTION = "interjection"
    PHRASE = "phrase"


class LicenseMode(str, Enum):
    APPROVED_DATASET = "approved_dataset"
    ADMIN_OWNED = "admin_owned"
    PUBLIC_DOMAIN_VERIFIED = "public_domain_verified"
    METADATA_ONLY = "metadata_only"
    DISABLED_PENDING_LICENSE = "disabled_pending_license"
    API_PENDING_LICENSE = "api_pending_license"


class ContentUsage(str, Enum):
    FULL_TEXT = "full_text"
    METADATA_ONLY = "metadata_only"
    LABEL_ONLY = "label_only"


class NormalizedSourceRecord(BaseModel):
    """Policy-filtered record safe to persist in temporary job state."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    record_id: str = Field(min_length=1, max_length=500)
    source_name: str = Field(min_length=1, max_length=100)
    source_url: str | None = Field(default=None, max_length=1000)
    license_mode: LicenseMode
    content_usage: ContentUsage
    title: str | None = Field(default=None, max_length=500)
    word: str | None = Field(default=None, max_length=255)
    part_of_speech: PartOfSpeech = PartOfSpeech.PHRASE
    definition: str | None = None
    translation_vi: str | None = None
    example: str | None = None
    declared_cefr: CEFRLevel | None = None
    declared_topic: str = Field(default="general", min_length=1, max_length=100)
    published_at: datetime | None = None
    checksum: str | None = Field(default=None, max_length=64)
    source_version: str | None = Field(default=None, max_length=64)
    source_record_id: str | None = Field(default=None, max_length=500)
    license_id: str | None = Field(default=None, max_length=128)
    license_url: str | None = Field(default=None, max_length=1000)
    attribution_text: str | None = Field(default=None, max_length=2000)
    raw_checksum: str | None = Field(default=None, max_length=64)
    lineage: dict[str, Any] | None = None
    source_content_usage: str | None = Field(default=None, max_length=32)
    metadata: dict[str, Any] = Field(default_factory=dict)
    classification_confidence: float = Field(default=1.0, ge=0.0, le=1.0)


class SourceRecordBatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_name: str | None = Field(default=None, min_length=1, max_length=100)
    records: list[dict[str, Any]] = Field(min_length=1)


class RecordBatchResponse(BaseModel):
    accepted_records: int
    stored_records: int


class SourceSnapshotDescriptor(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    source_id: str = Field(min_length=1, max_length=100)
    source_name: str = Field(min_length=1, max_length=100)
    source_version: str = Field(min_length=1, max_length=64)
    snapshot_id: str = Field(min_length=1, max_length=500)
    official_url: str = Field(min_length=1, max_length=1000)
    license_id: str = Field(min_length=1, max_length=128)
    license_url: str = Field(min_length=1, max_length=1000)
    attribution_text: str = Field(min_length=1, max_length=2000)
    retrieved_at: datetime
    raw_checksum: str = Field(pattern=r"^[a-f0-9]{64}$")
    normalized_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    normalized_bytes: int = Field(gt=0)
    record_checksum_root: str = Field(pattern=r"^[a-f0-9]{64}$")
    adapter_version: int = Field(ge=1)
    record_count: int = Field(gt=0)
    status: Literal["active"] = "active"
    enabled: bool


class SnapshotReference(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_id: str = Field(min_length=1, max_length=100)
    source_version: str = Field(min_length=1, max_length=64)
    snapshot_id: str = Field(min_length=1, max_length=500)


class SnapshotAttachmentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    snapshots: list[SnapshotReference] = Field(min_length=1, max_length=20)


class SnapshotAttachmentResponse(BaseModel):
    attached_snapshots: int
    stored_records: int


class ExerciseMix(BaseModel):
    model_config = ConfigDict(extra="forbid")

    speaking: int = Field(default=2, ge=0, le=20)
    listening: int = Field(default=2, ge=0, le=20)


class GenerationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    levels: list[CEFRLevel] = Field(
        min_length=1,
        max_length=6,
        validation_alias=AliasChoices("levels", "selected_levels"),
    )
    sources: list[str] | None = Field(default=None, min_length=1)
    upload_id: str | None = None
    title_focus: str | None = Field(default=None, max_length=255)
    topic_focus: list[str] = Field(default_factory=list, max_length=20)
    units_per_course: int = Field(default=3, ge=1, le=10)
    lessons_per_unit: int = Field(default=3, ge=1, le=20)
    words_per_lesson: int = Field(
        default=10,
        ge=8,
        le=12,
        validation_alias=AliasChoices("words_per_lesson", "vocabulary_per_lesson"),
    )
    exercises_per_lesson: int = Field(
        default=10,
        ge=4,
        le=20,
        validation_alias=AliasChoices("exercises_per_lesson", "exercise_count"),
    )
    exercise_mix: ExerciseMix = Field(default_factory=ExerciseMix)
    confidence_threshold: float = Field(default=0.7, ge=0.0, le=1.0)
    revision: bool = False
    apply_on_success: bool = False

    @field_validator("levels")
    @classmethod
    def unique_levels(cls, value: list[CEFRLevel]) -> list[CEFRLevel]:
        return list(dict.fromkeys(value))

    @field_validator("sources")
    @classmethod
    def normalize_sources(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        return list(
            dict.fromkeys(
                source.strip().lower()
                for source in value
                if source.strip()
            )
        )

    @model_validator(mode="after")
    def validate_exercise_mix(self):
        if (
            self.exercise_mix.speaking + self.exercise_mix.listening
            > self.exercises_per_lesson
        ):
            raise ValueError(
                "speaking and listening exercises must fit inside the lesson total"
            )
        return self


class ExerciseArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1, max_length=100)
    type: Literal[
        "multiple_choice",
        "true_false",
        "fill_blank",
        "translate",
        "matching",
        "reorder",
    ]
    ui_type: str = Field(min_length=1, max_length=100)
    question: str = Field(min_length=1)
    options: list[Any] | None = None
    correct_answer: str = Field(min_length=1)
    explanation: str | None = None
    hint: str | None = None
    audio_url: str | None = None
    image_url: str | None = None
    difficulty: int = Field(default=1, ge=1, le=5)
    points: int = Field(default=10, ge=0)


class VocabularyArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    word: str = Field(min_length=1, max_length=255)
    definition: str = Field(min_length=1)
    translation_vi: str | None = None
    example: str | None = None
    pronunciation: str | None = Field(default=None, max_length=100)
    audio_url: str | None = Field(default=None, max_length=500)
    part_of_speech: PartOfSpeech
    difficulty_level: CEFRLevel
    topic: str = "general"
    source_name: str = "generated"
    source_url: str | None = None
    license_mode: str = "generated"
    source_checksum: str | None = None
    source_version: str | None = Field(default=None, max_length=64)
    source_record_id: str | None = Field(default=None, max_length=500)
    license_id: str | None = Field(default=None, max_length=128)
    license_url: str | None = Field(default=None, max_length=1000)
    attribution_text: str | None = Field(default=None, max_length=2000)
    raw_checksum: str | None = Field(default=None, pattern=r"^[a-f0-9]{64}$")
    record_checksum: str | None = Field(default=None, pattern=r"^[a-f0-9]{64}$")
    lineage: dict[str, Any] | None = None
    content_usage: str | None = Field(default=None, max_length=32)


class LessonArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    order_index: int = Field(ge=0)
    vocabulary: list[VocabularyArtifact] = Field(min_length=1)
    exercises: list[ExerciseArtifact] = Field(min_length=1)
    estimated_minutes: int = Field(default=10, ge=1, le=120)
    xp_reward: int = Field(default=20, ge=0)


class UnitArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    order_index: int = Field(ge=0)
    lessons: list[LessonArtifact] = Field(min_length=1)


class CourseArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    language: str = Field(default="en", min_length=2, max_length=10)
    level: CEFRLevel
    tags: list[str] = Field(default_factory=list)
    units: list[UnitArtifact] = Field(min_length=1)


class QualityArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    blocking_errors: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    metrics: dict[str, Any] = Field(default_factory=dict)


class ArtifactSourceManifest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    snapshot_id: str = Field(min_length=1, max_length=500)
    source_name: str = Field(min_length=1, max_length=100)
    source_version: str = Field(min_length=1, max_length=64)
    official_url: str = Field(min_length=1, max_length=1000)
    license_id: str = Field(min_length=1, max_length=128)
    license_url: str = Field(min_length=1, max_length=1000)
    attribution_text: str = Field(min_length=1, max_length=2000)
    retrieved_at: datetime
    raw_checksum: str = Field(pattern=r"^[a-f0-9]{64}$")
    normalized_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    normalized_bytes: int = Field(gt=0)
    record_checksum_root: str = Field(pattern=r"^[a-f0-9]{64}$")
    adapter_version: int = Field(ge=1)
    record_count: int = Field(gt=0)


class ContentAgentArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[2] = 2
    prompt_version: Literal["cefr-course-v2"] = "cefr-course-v2"
    generation_key: str = Field(pattern=r"^[a-f0-9]{64}$")
    source_manifest: list[ArtifactSourceManifest] = Field(min_length=1)
    courses: list[CourseArtifact] = Field(min_length=1)
    quality: QualityArtifact = Field(default_factory=QualityArtifact)
