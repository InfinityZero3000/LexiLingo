"""Transactional application of validated CEFR course artifacts."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_agent import (
    ContentAgentJob,
    ContentAgentUpload,
    ContentProvenance,
    LessonVocabularyItem,
)
from app.models.course import Course, Lesson, Unit
from app.schemas.content_agent import ContentAgentArtifact, VocabularyArtifact
from app.services.content_agent_jobs import ContentAgentJobService
from app.services.content_agent_validation import validate_artifact
from app.services.vocabulary_catalog import normalize_word, upsert_vocabulary_batch

_STORABLE_LICENSE_MODES = frozenset(
    {"generated", "approved_dataset", "admin_owned", "public_domain_verified"}
)


def _translation_payload(vocabulary: VocabularyArtifact) -> dict | None:
    payload: dict[str, object] = {}
    if vocabulary.translation_vi:
        payload["vi"] = vocabulary.translation_vi
    if vocabulary.example:
        payload["examples"] = [vocabulary.example]
    return payload or None


def _course_tags(course_level: str, source_topics: list[str]) -> dict:
    topics = list(dict.fromkeys(t for t in source_topics if t))
    return {
        "categories": ["cefr", course_level],
        "source": ["content-agent"],
        "topics": topics or ["general"],
    }


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

        manifest_sources = {
            str(entry.get("source_name") or "")
            for entry in (job.artifact.get("source_manifest") or [])
            if isinstance(entry, dict)
        }
        upload = (
            await db.get(ContentAgentUpload, job.upload_id)
            if job.upload_id is not None
            else None
        )
        admin_upload_context = None
        if "admin_upload" in manifest_sources:
            if upload is None:
                raise ValueError("Admin upload content requires a surviving upload")
            if upload.expires_at <= datetime.now(UTC):
                raise ValueError("Referenced upload has expired")
            if not upload.rights_confirmed:
                raise ValueError("Upload rights attestation is required")
            admin_upload_context = {
                "checksum": upload.checksum,
                "row_count": upload.row_count,
            }

        # --- Pure artifact validation gate -----------------------------------
        pinned_snapshots = list((job.config or {}).get("pinned_snapshots") or [])
        report = validate_artifact(
            job.artifact,
            pinned_snapshots=pinned_snapshots,
            admin_upload=admin_upload_context,
        )
        if report.is_blocking:
            codes = ", ".join(e.code for e in report.blocking_errors)
            raise ValueError(f"Artifact failed validation gates: {codes}")

        artifact = ContentAgentArtifact.model_validate(job.artifact)
        if artifact.quality.blocking_errors:
            raise ValueError("Artifact has blocking validation errors")
        # --- Gather all vocab items for batch upsert -------------------------
        all_vocab_items: list[dict] = []
        for course_data in artifact.courses:
            for unit_data in course_data.units:
                for lesson_data in unit_data.lessons:
                    for vocab_data in lesson_data.vocabulary:
                        if vocab_data.license_mode not in _STORABLE_LICENSE_MODES:
                            raise ValueError(
                                "Artifact contains vocabulary from a non-storable "
                                f"source mode: {vocab_data.license_mode}"
                            )
                        all_vocab_items.append(
                            {
                                "word": vocab_data.word,
                                "part_of_speech": vocab_data.part_of_speech,
                                "definition": vocab_data.definition,
                                "translation": _translation_payload(vocab_data),
                                "pronunciation": vocab_data.pronunciation,
                                "audio_url": vocab_data.audio_url,
                                "difficulty_level": vocab_data.difficulty_level,
                                "topic": vocab_data.topic,
                                "source_name": vocab_data.source_name,
                            }
                        )

        await ContentAgentJobService.transition(db, job, "applying", percent=100)

        # Batch upsert all vocabulary, get stable word→id map
        vocab_identity = await upsert_vocabulary_batch(db, all_vocab_items)

        created_course_ids: list[uuid.UUID] = []
        for course_data in artifact.courses:
            # Collect unique topics across all lessons in the course
            course_topics: list[str] = []
            for unit_data in course_data.units:
                for lesson_data in unit_data.lessons:
                    for vocab_data in lesson_data.vocabulary:
                        if vocab_data.topic not in course_topics:
                            course_topics.append(vocab_data.topic)

            course = Course(
                title=course_data.title,
                description=course_data.description,
                language=course_data.language,
                level=course_data.level,
                tags=_course_tags(course_data.level, course_topics),
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
                        outcome=lesson_data.outcome,
                        order_index=lesson_data.order_index,
                        lesson_type="vocabulary",
                        pass_threshold=80,
                        estimated_minutes=lesson_data.estimated_minutes,
                        xp_reward=lesson_data.xp_reward,
                        total_exercises=len(exercises),
                        content={
                            "version": 2,
                            "generated_by": "cefr-content-agent",
                            "source_job_id": str(job.id),
                            "exercises": exercises,
                        },
                    )
                    db.add(lesson)
                    await db.flush()

                    for vocab_order, vocab_data in enumerate(lesson_data.vocabulary):
                        key = (
                            normalize_word(vocab_data.word),
                            vocab_data.part_of_speech,
                        )
                        vocab_id = vocab_identity[key]

                        membership_exists = await db.scalar(
                            select(LessonVocabularyItem.id).where(
                                LessonVocabularyItem.lesson_id == lesson.id,
                                LessonVocabularyItem.vocabulary_id == vocab_id,
                            )
                        )
                        if membership_exists is None:
                            db.add(
                                LessonVocabularyItem(
                                    lesson_id=lesson.id,
                                    vocabulary_id=vocab_id,
                                    source_job_id=job.id,
                                    order_index=vocab_order,
                                )
                            )
                        db.add(
                            ContentProvenance(
                                job_id=job.id,
                                entity_type="vocabulary",
                                entity_id=vocab_id,
                                source_name=vocab_data.source_name,
                                source_url=vocab_data.source_url,
                                license_mode=vocab_data.license_mode,
                                source_checksum=vocab_data.source_checksum,
                                is_generated=vocab_data.license_mode == "generated",
                                source_version=vocab_data.source_version,
                                license_id=vocab_data.license_id,
                                license_url=vocab_data.license_url,
                                attribution_text=vocab_data.attribution_text,
                                raw_checksum=vocab_data.raw_checksum,
                                record_checksum=(
                                    vocab_data.record_checksum
                                    or vocab_data.source_checksum
                                ),
                                lineage=vocab_data.lineage,
                                content_usage=vocab_data.content_usage,
                                rights_confirmed_at=(
                                    upload.rights_confirmed_at
                                    if upload is not None
                                    and vocab_data.source_name == "admin_upload"
                                    else None
                                ),
                                rights_statement_version=(
                                    "admin-upload-v1"
                                    if upload is not None
                                    and vocab_data.source_name == "admin_upload"
                                    else None
                                ),
                                metadata_json={
                                    "lesson_id": str(lesson.id),
                                    "topic": vocab_data.topic,
                                    "source_record_id": (
                                        vocab_data.source_record_id
                                    ),
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
