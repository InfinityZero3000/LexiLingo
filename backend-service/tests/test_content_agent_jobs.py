import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.content_agent import ContentAgentJob, ContentAgentUpload
from app.schemas.content_agent import ContentAgentJobCreate
from app.services.content_agent_jobs import ContentAgentJobService


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
