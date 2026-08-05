import uuid
from types import SimpleNamespace

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.content_agent import ContentAgentJob
from app.models.rbac import AuditLog
from app.routes.content_agent import update_job_record
from app.schemas.content_agent import ContentAgentRecordUpdate
from fastapi import HTTPException


@pytest.fixture
async def db_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [ContentAgentJob.__table__, AuditLog.__table__]
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


def _admin(user_id=None):
    return SimpleNamespace(id=user_id or uuid.uuid4(), role_level=2)


def _job(admin_id, exercise_id="exercise-0"):
    artifact = {
        "courses": [
            {
                "units": [
                    {
                        "lessons": [
                            {
                                "title": "Book a hotel room",
                                "outcome": "You can ask for a room.",
                                "exercises": [
                                    {
                                        "id": exercise_id,
                                        "type": "fill_blank",
                                        "ui_type": "fill_in_the_blank",
                                        "question": "Original question",
                                        "correct_answer": "original",
                                    }
                                ],
                            }
                        ]
                    }
                ]
            }
        ]
    }
    return ContentAgentJob(
        requested_by_id=admin_id,
        status="preview_ready",
        request_hash="a" * 64,
        revision=1,
        config={},
        progress={"stage": "preview_ready", "percent": 100},
        artifact=artifact,
    )


@pytest.mark.asyncio
async def test_update_job_record_edits_exercise_and_lesson_outcome(db_session):
    admin = _admin()
    job = _job(admin.id)
    db_session.add(job)
    await db_session.commit()

    response = await update_job_record(
        job.id,
        "exercise-0",
        ContentAgentRecordUpdate(
            question="Edited question",
            correct_answer="edited",
            lesson_outcome="You can book a hotel room by phone.",
        ),
        db_session,
        admin,
    )

    exercise = response.data["artifact"]["courses"][0]["units"][0]["lessons"][0]["exercises"][0]
    lesson = response.data["artifact"]["courses"][0]["units"][0]["lessons"][0]
    assert exercise["question"] == "Edited question"
    assert exercise["correct_answer"] == "edited"
    assert lesson["outcome"] == "You can book a hotel room by phone."


@pytest.mark.asyncio
async def test_update_job_record_404_for_unknown_record_id(db_session):
    admin = _admin()
    job = _job(admin.id)
    db_session.add(job)
    await db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        await update_job_record(
            job.id,
            "does-not-exist",
            ContentAgentRecordUpdate(question="x"),
            db_session,
            admin,
        )
    assert exc_info.value.status_code == 404
