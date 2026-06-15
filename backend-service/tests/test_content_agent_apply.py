import pytest
from sqlalchemy import func, select
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
        "generation_key": "generation-key",
        "source_manifest": [
            {
                "source_id": "admin_upload",
                "snapshot_id": "admin_upload:v1:abc123",
                "license_mode": "admin_owned",
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


async def test_apply_reuses_vocabulary_and_is_idempotent(content_agent_db):
    existing = VocabularyItem(
        word="hello",
        definition="Curated definition",
        part_of_speech="noun",
        difficulty_level="A1",
    )
    job = ContentAgentJob(
        requested_by_id=None,
        status="preview_ready",
        request_hash="a" * 64,
        revision=1,
        config={},
        progress={"stage": "preview_ready", "percent": 100},
        artifact=_artifact(),
    )
    content_agent_db.add_all([existing, job])
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
    job = ContentAgentJob(
        requested_by_id=None,
        status="preview_ready",
        request_hash="b" * 64,
        revision=1,
        config={},
        progress={"stage": "preview_ready", "percent": 100},
        artifact=artifact,
    )
    content_agent_db.add_all([existing, job])
    await content_agent_db.commit()

    await ContentAgentApplyService.apply(content_agent_db, job.id)
    await content_agent_db.commit()

    assert await content_agent_db.scalar(
        select(func.count(VocabularyItem.id))
    ) == 8
    await content_agent_db.refresh(existing)
    assert existing.definition == "Curated definition"
