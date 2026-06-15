"""Transactional application of validated CEFR course artifacts."""

from __future__ import annotations

import re
import unicodedata
import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_agent import (
    ContentAgentJob,
    ContentProvenance,
    LessonVocabularyItem,
)
from app.models.course import Course, Lesson, Unit
from app.models.vocabulary import VocabularyItem
from app.schemas.content_agent import ContentAgentArtifact, VocabularyArtifact
from app.services.content_agent_jobs import ContentAgentJobService


def normalize_vocabulary_word(word: str) -> str:
    normalized = unicodedata.normalize("NFKC", word)
    normalized = (
        normalized.casefold()
        .replace("’", "'")
        .replace("‘", "'")
        .replace("–", "-")
        .replace("—", "-")
        .replace("‑", "-")
    )
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def _translation_payload(vocabulary: VocabularyArtifact) -> dict | None:
    payload: dict[str, object] = {}
    if vocabulary.translation_vi:
        payload["vi"] = vocabulary.translation_vi
    if vocabulary.example:
        payload["examples"] = [vocabulary.example]
    return payload or None


def _validate_source_policy(artifact: ContentAgentArtifact) -> None:
    allowed_modes = {
        "generated",
        "approved_dataset",
        "admin_owned",
        "public_domain_verified",
    }
    for course in artifact.courses:
        for unit in course.units:
            for lesson in unit.lessons:
                for vocabulary in lesson.vocabulary:
                    if vocabulary.license_mode not in allowed_modes:
                        raise ValueError(
                            "Artifact contains vocabulary from a non-storable "
                            f"source mode: {vocabulary.license_mode}"
                        )


class ContentAgentApplyService:
    @staticmethod
    async def apply(
        db: AsyncSession, job_id: uuid.UUID
    ) -> tuple[ContentAgentJob, list[uuid.UUID]]:
        job = await ContentAgentJobService.get(db, job_id, lock=True)
        if job is None:
            raise LookupError("Content-agent job not found")
        if job.status == "completed":
            values = job.created_entity_ids.get(
                "course_ids", job.created_entity_ids.get("courses", [])
            )
            return job, [uuid.UUID(value) for value in values]
        if job.status != "preview_ready":
            raise ValueError("Only preview-ready jobs can be applied")
        if job.blocking_errors:
            raise ValueError("Job has blocking validation errors")
        if not job.artifact:
            raise ValueError("Job has no preview artifact")

        artifact = ContentAgentArtifact.model_validate(job.artifact)
        if artifact.quality.blocking_errors:
            raise ValueError("Artifact has blocking validation errors")
        _validate_source_policy(artifact)

        await ContentAgentJobService.transition(db, job, "applying", percent=100)
        created_course_ids: list[uuid.UUID] = []
        existing_vocabulary = await db.scalars(select(VocabularyItem))
        vocabulary_index = {
            (
                normalize_vocabulary_word(vocabulary.word),
                str(vocabulary.part_of_speech),
            ): vocabulary
            for vocabulary in existing_vocabulary
        }

        for course_data in artifact.courses:
            course = Course(
                title=course_data.title,
                description=course_data.description,
                language=course_data.language,
                level=course_data.level,
                tags=list(dict.fromkeys([*course_data.tags, "generated", "content-agent"])),
                is_published=False,
                total_lessons=sum(len(unit.lessons) for unit in course_data.units),
                total_xp=sum(
                    lesson.xp_reward
                    for unit in course_data.units
                    for lesson in unit.lessons
                ),
                estimated_duration=sum(
                    lesson.estimated_minutes
                    for unit in course_data.units
                    for lesson in unit.lessons
                ),
            )
            db.add(course)
            await db.flush()
            created_course_ids.append(course.id)
            db.add(
                ContentProvenance(
                    job_id=job.id,
                    entity_type="course",
                    entity_id=course.id,
                    source_name="content_agent",
                    license_mode="generated",
                    is_generated=True,
                    metadata_json={"generation_key": artifact.generation_key},
                )
            )

            for unit_data in course_data.units:
                unit = Unit(
                    course_id=course.id,
                    title=unit_data.title,
                    description=unit_data.description,
                    order_index=unit_data.order_index,
                    total_lessons=len(unit_data.lessons),
                )
                db.add(unit)
                await db.flush()

                for lesson_data in unit_data.lessons:
                    exercises = [
                        exercise.model_dump(mode="json")
                        for exercise in lesson_data.exercises
                    ]
                    lesson = Lesson(
                        course_id=course.id,
                        unit_id=unit.id,
                        title=lesson_data.title,
                        description=lesson_data.description,
                        order_index=lesson_data.order_index,
                        lesson_type="vocabulary",
                        pass_threshold=80,
                        estimated_minutes=lesson_data.estimated_minutes,
                        xp_reward=lesson_data.xp_reward,
                        total_exercises=len(exercises),
                        content={
                            "exercises": exercises,
                            "version": 1,
                            "generated_by": "cefr-content-agent",
                        },
                    )
                    db.add(lesson)
                    await db.flush()

                    for vocabulary_order, vocabulary_data in enumerate(
                        lesson_data.vocabulary
                    ):
                        normalized = normalize_vocabulary_word(vocabulary_data.word)
                        vocabulary_key = (
                            normalized,
                            vocabulary_data.part_of_speech,
                        )
                        vocabulary = vocabulary_index.get(vocabulary_key)
                        if vocabulary is None:
                            vocabulary = VocabularyItem(
                                word=normalized,
                                definition=vocabulary_data.definition,
                                translation=_translation_payload(vocabulary_data),
                                pronunciation=vocabulary_data.pronunciation,
                                audio_url=vocabulary_data.audio_url,
                                part_of_speech=vocabulary_data.part_of_speech,
                                difficulty_level=vocabulary_data.difficulty_level,
                                course_id=course.id,
                                lesson_id=lesson.id,
                                tags={
                                    "source": [
                                        "content-agent",
                                        vocabulary_data.source_name,
                                    ],
                                    "topic": [vocabulary_data.topic],
                                },
                            )
                            db.add(vocabulary)
                            await db.flush()
                            vocabulary_index[vocabulary_key] = vocabulary
                        else:
                            if not vocabulary.definition.strip():
                                vocabulary.definition = vocabulary_data.definition
                            if vocabulary.translation is None:
                                vocabulary.translation = _translation_payload(
                                    vocabulary_data
                                )
                            if not vocabulary.pronunciation:
                                vocabulary.pronunciation = (
                                    vocabulary_data.pronunciation
                                )
                            if not vocabulary.audio_url:
                                vocabulary.audio_url = vocabulary_data.audio_url

                        membership_exists = await db.scalar(
                            select(LessonVocabularyItem.id).where(
                                LessonVocabularyItem.lesson_id == lesson.id,
                                LessonVocabularyItem.vocabulary_id == vocabulary.id,
                            )
                        )
                        if membership_exists is None:
                            db.add(
                                LessonVocabularyItem(
                                    lesson_id=lesson.id,
                                    vocabulary_id=vocabulary.id,
                                    source_job_id=job.id,
                                    order_index=vocabulary_order,
                                )
                            )
                        db.add(
                            ContentProvenance(
                                job_id=job.id,
                                entity_type="vocabulary",
                                entity_id=vocabulary.id,
                                source_name=vocabulary_data.source_name,
                                source_url=vocabulary_data.source_url,
                                license_mode=vocabulary_data.license_mode,
                                source_checksum=vocabulary_data.source_checksum,
                                is_generated=vocabulary_data.license_mode
                                == "generated",
                                metadata_json={
                                    "lesson_id": str(lesson.id),
                                    "topic": vocabulary_data.topic,
                                },
                            )
                        )

        job.created_entity_ids = {
            "course_ids": [str(course_id) for course_id in created_course_ids]
        }
        job.completed_at = datetime.now(UTC)
        await ContentAgentJobService.transition(db, job, "completed", percent=100)
        await db.flush()
        return job, created_course_ids
