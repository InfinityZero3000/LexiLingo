from unittest.mock import AsyncMock

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.models.api_cache import APICacheEntry
from app.services import api_cache_service
from app.services.api_cache_service import APICacheService
from app.services.quota_manager import QuotaStatus


@pytest.mark.asyncio
async def test_zero_cost_fetch_bypasses_quota_manager(monkeypatch):
    service = APICacheService(db=object())
    monkeypatch.setattr(api_cache_service.RedisClient, "get_instance", AsyncMock(return_value=None))
    monkeypatch.setattr(service, "_get_db_entry", AsyncMock(return_value=None))
    monkeypatch.setattr(service, "_warm_redis", AsyncMock())
    monkeypatch.setattr(service, "_upsert_db_entry", AsyncMock())
    check_status = AsyncMock(side_effect=AssertionError("quota should be skipped"))
    record_request = AsyncMock(side_effect=AssertionError("quota should be skipped"))
    monkeypatch.setattr(api_cache_service.QuotaManager, "check_status", check_status)
    monkeypatch.setattr(api_cache_service.QuotaManager, "record_request", record_request)

    result = await service.get_or_fetch(
        cache_key="youtube:captions:abc:en",
        api_name="youtube",
        fetch_fn=AsyncMock(return_value={"segments": []}),
        cost=0,
    )

    assert result.source == "api"
    assert result.data == {"segments": []}
    check_status.assert_not_called()
    record_request.assert_not_called()


@pytest.mark.asyncio
async def test_fetch_forwards_quota_cost(monkeypatch):
    service = APICacheService(db=object())
    monkeypatch.setattr(api_cache_service.RedisClient, "get_instance", AsyncMock(return_value=None))
    monkeypatch.setattr(service, "_get_db_entry", AsyncMock(return_value=None))
    monkeypatch.setattr(service, "_warm_redis", AsyncMock())
    monkeypatch.setattr(service, "_upsert_db_entry", AsyncMock())
    check_status = AsyncMock(return_value=QuotaStatus.NORMAL)
    record_request = AsyncMock(return_value=QuotaStatus.NORMAL)
    monkeypatch.setattr(api_cache_service.QuotaManager, "check_status", check_status)
    monkeypatch.setattr(api_cache_service.QuotaManager, "record_request", record_request)

    result = await service.get_or_fetch(
        cache_key="youtube:search:q:english",
        api_name="youtube",
        fetch_fn=AsyncMock(return_value={"videos": []}),
        cost=100,
    )

    assert result.source == "api"
    assert result.data == {"videos": []}
    check_status.assert_awaited_once_with("youtube", cost=100)
    record_request.assert_awaited_once_with("youtube", cost=100)


@pytest.mark.asyncio
async def test_failed_cache_write_does_not_poison_session(monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as connection:
        await connection.run_sync(APICacheEntry.__table__.create)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        session.add(APICacheEntry(cache_key="duplicate", api_name="test", data="{}"))
        await session.commit()

        service = APICacheService(db=session)
        monkeypatch.setattr(service, "_get_db_entry", AsyncMock(return_value=None))
        await service._upsert_db_entry("duplicate", "test", "{}")

        session.add(APICacheEntry(cache_key="still-works", api_name="test", data="{}"))
        await session.commit()

        assert await session.scalar(
            select(APICacheEntry).where(APICacheEntry.cache_key == "still-works")
        )

    await engine.dispose()
