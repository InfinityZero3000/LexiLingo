import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import event, func, select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.crud.vocabulary import vocabulary_crud
from app.models.content_agent import (
    ContentAgentJob,
    ContentAgentUpload,
    ContentProvenance,
    LessonVocabularyItem,
)
from app.models.course import Course, Lesson, Unit
from app.models.vocabulary import VocabularyItem
from app.services.content_agent_apply import ContentAgentApplyService
from app.services.vocabulary_catalog import normalize_word


@pytest.fixture
async def content_agent_db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        ContentAgentUpload.__table__,
        ContentAgentJob.__table__,
        Course.__table__,
        Unit.__table__,
        Lesson.__table__,
        VocabularyItem.__table__,
        LessonVocabularyItem.__table__,
        ContentProvenance.__table__,
    ]
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection, tables=tables
            )
        )
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


def _artifact() -> dict:
    vocabulary = [
        {
            "word": "HELLO" if index == 0 else f"word{index}",
            "definition": f"Generated definition {index}",
            "part_of_speech": "noun",
            "difficulty_level": "A1",
            "topic": "daily_life",
            "source_name": "admin_upload",
            "license_mode": "admin_owned",
            "source_version": "job-upload-v1",
            "source_record_id": f"admin_upload:{index}",
            "license_id": "LicenseRef-Admin-Owned",
            "license_url": "https://lexilingo.me/legal/content-upload-rights",
            "attribution_text": "Administrator-owned or licensed upload",
            "raw_checksum": "b" * 64,
            "record_checksum": f"{index:064x}",
            "source_checksum": f"{index:064x}",
            "lineage": {
                "adapter": "admin_upload",
                "adapter_version": 1,
                "raw_path": "content-agent-upload/test",
                "source_location": f"row:{index}",
            },
            "content_usage": "full_text",
        }
        for index in range(8)
    ]
    exercises = [
        {
            "id": f"exercise-{index}",
            "type": "translate",
            "ui_type": "speaking_repeat",
            "question": f"Question {index}",
            "correct_answer": f"Answer {index}",
        }
        for index in range(4)
    ]
    return {
        "schema_version": 2,
        "prompt_version": "cefr-course-v2",
        "generation_key": "a" * 64,
        "source_manifest": [
            {
                "snapshot_id": f"admin_upload:job-upload-v1:{'b' * 64}",
                "source_name": "admin_upload",
                "source_version": "job-upload-v1",
                "official_url": "https://lexilingo.me/admin/content-agent/uploads",
                "license_id": "LicenseRef-Admin-Owned",
                "license_url": "https://lexilingo.me/legal/content-upload-rights",
                "attribution_text": "Administrator-owned or licensed upload",
                "retrieved_at": "2026-06-15T00:00:00Z",
                "raw_checksum": "b" * 64,
                "normalized_sha256": "c" * 64,
                "normalized_bytes": 128,
                "record_checksum_root": "d" * 64,
                "adapter_version": 1,
                "record_count": 8,
            }
        ],
        "courses": [
            {
                "title": "English A1 Foundations",
                "level": "A1",
                "units": [
                    {
                        "title": "Daily Life",
                        "order_index": 0,
                        "lessons": [
                            {
                                "title": "Greetings",
                                "order_index": 0,
                                "vocabulary": vocabulary,
                                "exercises": exercises,
                            }
                        ],
                    }
                ],
            }
        ],
    }


def _upload() -> ContentAgentUpload:
    return ContentAgentUpload(
        id=uuid.uuid4(),
        uploaded_by_id=uuid.uuid4(),
        filename="admin.csv",
        checksum="b" * 64,
        row_count=8,
        schema_version=1,
        records=[],
        expires_at=datetime.now(UTC) + timedelta(days=1),
        rights_confirmed=True,
        rights_confirmed_at=datetime.now(UTC),
        uploader_id=uuid.uuid4(),
    )


async def test_apply_reuses_vocabulary_and_is_idempotent(content_agent_db):
    existing = VocabularyItem(
        word="hello",
        definition="Curated definition",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    upload = _upload()
    job = ContentAgentJob(
        requested_by_id=None,
        upload_id=upload.id,
        status="preview_ready",
        request_hash="a" * 64,
        revision=1,
        config={},
        progress={"stage": "preview_ready", "percent": 100},
        artifact=_artifact(),
    )
    content_agent_db.add_all([existing, upload, job])
    await content_agent_db.commit()

    applied_job, course_ids = await ContentAgentApplyService.apply(
        content_agent_db, job.id
    )
    await content_agent_db.commit()

    assert applied_job.status == "completed"
    assert len(course_ids) == 1
    assert (
        await content_agent_db.scalar(
            select(func.count(Course.id))
        )
        == 1
    )
    assert (
        await content_agent_db.scalar(
            select(func.count(VocabularyItem.id))
        )
        == 8
    )
    assert (
        await content_agent_db.scalar(
            select(func.count(LessonVocabularyItem.id))
        )
        == 8
    )
    await content_agent_db.refresh(existing)
    assert existing.definition == "Curated definition"
    lesson_id = await content_agent_db.scalar(select(Lesson.id))
    lesson_items = await vocabulary_crud.get_vocabulary_items(
        content_agent_db,
        course_id=course_ids[0],
        lesson_id=lesson_id,
        limit=20,
    )
    assert len(lesson_items) == 8
    assert existing in lesson_items
    provenance = await content_agent_db.scalar(
        select(ContentProvenance).where(
            ContentProvenance.entity_type == "vocabulary",
            ContentProvenance.entity_id == existing.id,
        )
    )
    assert provenance is not None
    assert provenance.source_version == "job-upload-v1"
    assert provenance.license_id == "LicenseRef-Admin-Owned"
    assert provenance.raw_checksum == "b" * 64
    assert provenance.lineage["adapter"] == "admin_upload"

    repeated_job, repeated_ids = await ContentAgentApplyService.apply(
        content_agent_db, job.id
    )

    assert repeated_job.id == job.id
    assert repeated_ids == course_ids
    assert repeated_job.created_entity_ids == {
        "course_ids": [str(course_ids[0])]
    }


async def test_apply_deduplicates_unicode_normalized_vocabulary(content_agent_db):
    raw_word = "Café’s—Menu"
    artifact = _artifact()
    artifact["courses"][0]["units"][0]["lessons"][0]["vocabulary"][0]["word"] = raw_word
    existing = VocabularyItem(
        word=normalize_word(raw_word),
        definition="Curated definition",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    upload = _upload()
    job = ContentAgentJob(
        requested_by_id=None,
        upload_id=upload.id,
        status="preview_ready",
        request_hash="b" * 64,
        revision=1,
        config={},
        progress={"stage": "preview_ready", "percent": 100},
        artifact=artifact,
    )
    content_agent_db.add_all([existing, upload, job])
    await content_agent_db.commit()

    await ContentAgentApplyService.apply(content_agent_db, job.id)
    await content_agent_db.commit()

    assert await content_agent_db.scalar(
        select(func.count(VocabularyItem.id))
    ) == 8
    await content_agent_db.refresh(existing)
    assert existing.definition == "Curated definition"


async def test_apply_bulk_inserts_lesson_memberships_without_selects(content_agent_db):
    upload = _upload()
    job = ContentAgentJob(
        requested_by_id=None,
        upload_id=upload.id,
        status="preview_ready",
        request_hash="c" * 64,
        revision=1,
        config={},
        progress={"stage": "preview_ready", "percent": 100},
        artifact=_artifact(),
    )
    content_agent_db.add_all([upload, job])
    await content_agent_db.commit()
    statements: list[str] = []

    def capture_membership_sql(_conn, _cursor, statement, *_args):
        if "lesson_vocabulary_items" in statement:
            statements.append(statement)

    engine = content_agent_db.bind.sync_engine
    event.listen(engine, "before_cursor_execute", capture_membership_sql)
    try:
        await ContentAgentApplyService.apply(content_agent_db, job.id)
    finally:
        event.remove(engine, "before_cursor_execute", capture_membership_sql)

    assert sum(statement.lstrip().upper().startswith("INSERT") for statement in statements) == 1
    assert not any(statement.lstrip().upper().startswith("SELECT") for statement in statements)
