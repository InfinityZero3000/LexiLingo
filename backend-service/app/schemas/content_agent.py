"""Pydantic contracts for CEFR content-agent jobs and artifacts."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

CEFRLevel = Literal["A1", "A2", "B1", "B2", "C1", "C2"]
PartOfSpeech = Literal[
    "noun",
    "verb",
    "adjective",
    "adverb",
    "pronoun",
    "preposition",
    "conjunction",
    "interjection",
    "phrase",
]


class NormalizedVocabularyRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    record_id: str = Field(min_length=1, max_length=500)
    source_name: str = Field(min_length=1, max_length=100)
    source_url: str | None = Field(default=None, max_length=1000)
    license_mode: str = Field(default="admin_owned", max_length=64)
    content_usage: Literal["full_text", "metadata_only", "label_only"] = "full_text"
    title: str | None = Field(default=None, max_length=500)
    word: str = Field(min_length=1, max_length=255)
    part_of_speech: PartOfSpeech = "noun"
    definition: str | None = None
    translation_vi: str | None = None
    example: str | None = None
    declared_cefr: CEFRLevel
    declared_topic: str = Field(default="general", min_length=1, max_length=100)
    published_at: datetime | None = None
    checksum: str | None = Field(default=None, max_length=64)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("word")
    @classmethod
    def clean_word(cls, value: str) -> str:
        cleaned = " ".join(value.strip().split())
        if not any(char.isalnum() for char in cleaned):
            raise ValueError("word must contain a letter or number")
        return cleaned


class ExerciseMix(BaseModel):
    speaking: int = Field(default=2, ge=0, le=20)
    listening: int = Field(default=2, ge=0, le=20)


class ContentAgentJobCreate(BaseModel):
    levels: list[CEFRLevel] = Field(min_length=1, max_length=6)
    sources: list[str] = Field(default_factory=lambda: ["existing_cefr"], min_length=1)
    # source_ids: resolved snapshot IDs pinned at job creation (populated by backend)
    source_ids: list[str] = Field(default_factory=list)
    upload_id: uuid.UUID | None = None
    title_focus: str | None = Field(default=None, max_length=255)
    topic_focus: list[str] = Field(default_factory=list, max_length=20)
    units_per_course: int = Field(default=3, ge=1, le=10)
    lessons_per_unit: int = Field(default=3, ge=1, le=20)
    words_per_lesson: int = Field(default=10, ge=8, le=12)
    exercises_per_lesson: int = Field(default=10, ge=4, le=20)
    exercise_mix: ExerciseMix = Field(default_factory=ExerciseMix)
    confidence_threshold: float = Field(default=0.7, ge=0.0, le=1.0)
    revision: bool = False
    apply_on_success: bool = False

    @field_validator("levels")
    @classmethod
    def unique_levels(cls, value: list[str]) -> list[str]:
        return list(dict.fromkeys(value))

    @field_validator("sources")
    @classmethod
    def unique_sources(cls, value: list[str]) -> list[str]:
        allowed = {
            "existing_cefr",
            "admin_upload",
            "oewn",
            "cmudict",
            "cefr_j",
            "wikidata",
            "tatoeba",
            "librispeech",
            "common_voice",
        }
        normalized = list(dict.fromkeys(item.strip().lower() for item in value))
        unknown = sorted(set(normalized) - allowed)
        if unknown:
            raise ValueError(f"unsupported sources: {', '.join(unknown)}")
        return normalized

    @model_validator(mode="after")
    def validate_upload_source(self):
        if "admin_upload" in self.sources and self.upload_id is None:
            raise ValueError("upload_id is required when admin_upload is selected")
        if self.upload_id is not None and "admin_upload" not in self.sources:
            raise ValueError("admin_upload must be selected when upload_id is provided")
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

    id: str
    type: Literal[
        "multiple_choice", "true_false", "fill_blank", "translate", "matching", "reorder"
    ]
    ui_type: str
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


class ContentAgentArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[2] = 2
    prompt_version: Literal["cefr-course-v2"] = "cefr-course-v2"
    generation_key: str
    source_manifest: list[dict[str, Any]] = Field(default_factory=list)
    courses: list[CourseArtifact] = Field(min_length=1)
    quality: QualityArtifact = Field(default_factory=QualityArtifact)


class ContentAgentUploadResponse(BaseModel):
    id: uuid.UUID
    filename: str
    checksum: str
    row_count: int
    expires_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ContentAgentJobResponse(BaseModel):
    id: uuid.UUID
    status: str
    request_hash: str
    revision: int
    config: dict[str, Any]
    progress: dict[str, Any]
    source_manifest: list[dict[str, Any]]
    warnings: list[str]
    blocking_errors: list[str]
    created_entity_ids: dict[str, Any]
    celery_task_id: str | None
    error_message: str | None
    created_at: datetime
    updated_at: datetime
    started_at: datetime | None
    completed_at: datetime | None

    model_config = ConfigDict(from_attributes=True)
