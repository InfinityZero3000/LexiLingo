from __future__ import annotations

import json
from pathlib import Path

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.content_agent import (
    ContentAgentJob,
    ContentAgentUpload,
    ContentProvenance,
    LessonVocabularyItem,
)
from app.models.course import Course, Lesson, Unit
from app.models.vocabulary import VocabularyItem
from app.services.content_agent_apply import ContentAgentApplyService
from app.services.content_agent_validation import validate_artifact

REPO_ROOT = Path(__file__).resolve().parents[3]
SHARED_FIXTURE = (
    REPO_ROOT
    / "contracts"
    / "content-agent"
    / "fixtures"
    / "licensed-etl-artifact-v2.json"
)


@pytest.fixture
async def licensed_flow_db():
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
                sync_connection,
                tables=tables,
            )
        )
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


async def test_pinned_licensed_artifact_applies_with_complete_provenance(
    licensed_flow_db,
):
    artifact = json.loads(SHARED_FIXTURE.read_text(encoding="utf-8"))
    manifest = artifact["source_manifest"][0]
    pin = {
        "source_id": manifest["source_name"],
        **manifest,
        "status": "active",
        "enabled": True,
    }
    report = validate_artifact(artifact, pinned_snapshots=[pin])
    assert not report.is_blocking

    job = ContentAgentJob(
        requested_by_id=None,
        status="preview_ready",
        request_hash="d" * 64,
        revision=1,
        config={
            "sources": ["oewn"],
            "pinned_snapshots": [pin],
        },
        progress={"stage": "preview_ready", "percent": 100},
        artifact=artifact,
    )
    licensed_flow_db.add(job)
    await licensed_flow_db.commit()

    applied, course_ids = await ContentAgentApplyService.apply(
        licensed_flow_db,
        job.id,
    )
    await licensed_flow_db.commit()

    assert applied.status == "completed"
    assert len(course_ids) == 1
    assert await licensed_flow_db.scalar(select(func.count(Course.id))) == 1
    assert (
        await licensed_flow_db.scalar(select(func.count(VocabularyItem.id)))
        == 8
    )
    provenance_rows = list(
        (
            await licensed_flow_db.execute(
                select(ContentProvenance).where(
                    ContentProvenance.entity_type == "vocabulary"
                )
            )
        )
        .scalars()
        .all()
    )
    assert len(provenance_rows) == 8
    assert all(row.source_version == "2025" for row in provenance_rows)
    assert all(row.license_id == "CC-BY-4.0" for row in provenance_rows)
    assert all(row.raw_checksum == "b" * 64 for row in provenance_rows)
    assert all(row.record_checksum for row in provenance_rows)
    assert all(row.lineage and row.lineage["adapter"] == "oewn" for row in provenance_rows)
    assert all(row.content_usage == "lexical" for row in provenance_rows)

    repeated, repeated_ids = await ContentAgentApplyService.apply(
        licensed_flow_db,
        job.id,
    )
    assert repeated.id == job.id
    assert repeated_ids == course_ids
    assert await licensed_flow_db.scalar(select(func.count(Course.id))) == 1
