import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.content_agent import ContentAgentJob, ContentAgentUpload
from app.schemas.content_agent import ContentAgentJobCreate
from app.services.content_agent_jobs import ContentAgentJobService, request_hash


@pytest.fixture
async def content_agent_db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=[
                    ContentAgentUpload.__table__,
                    ContentAgentJob.__table__,
                ],
            )
        )
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


async def test_duplicate_active_job_requires_revision(content_agent_db):
    config = ContentAgentJobCreate(levels=["A1"], sources=["existing_cefr"])
    requester = uuid.uuid4()

    first = await ContentAgentJobService.create(
        content_agent_db,
        requested_by_id=requester,
        config=config,
    )
    await content_agent_db.commit()

    with pytest.raises(ValueError, match="active job"):
        await ContentAgentJobService.create(
            content_agent_db,
            requested_by_id=requester,
            config=config,
        )

    revised = await ContentAgentJobService.create(
        content_agent_db,
        requested_by_id=requester,
        config=config.model_copy(update={"revision": True}),
    )

    assert first.revision == 1
    assert revised.revision == 2


async def test_job_state_machine_rejects_skipped_stages(content_agent_db):
    job = await ContentAgentJobService.create(
        content_agent_db,
        requested_by_id=uuid.uuid4(),
        config=ContentAgentJobCreate(levels=["A1"], sources=["existing_cefr"]),
    )

    with pytest.raises(ValueError, match="Invalid job transition"):
        await ContentAgentJobService.transition(
            content_agent_db, job, "generating"
        )


def test_request_hash_changes_when_snapshot_pin_changes():
    def config(snapshot_id: str) -> ContentAgentJobCreate:
        return ContentAgentJobCreate(
            levels=["A1"],
            sources=["oewn"],
            pinned_snapshots=[
                {
                    "source_id": "oewn",
                    "source_name": "oewn",
                    "source_version": "2025",
                    "snapshot_id": snapshot_id,
                    "official_url": "https://en-word.net/static/english-wordnet-2025.xml.gz",
                    "license_id": "CC-BY-4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "attribution_text": "Open English WordNet 2025",
                    "retrieved_at": "2026-06-15T00:00:00Z",
                    "raw_checksum": "a" * 64,
                    "normalized_sha256": "b" * 64,
                    "normalized_bytes": 100,
                    "record_checksum_root": "c" * 64,
                    "adapter_version": 1,
                    "record_count": 100,
                    "status": "active",
                    "enabled": True,
                }
            ],
        )

    assert request_hash(config("snapshot-a")) != request_hash(config("snapshot-b"))
