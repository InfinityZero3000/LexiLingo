import hashlib
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.course import CourseCRUD
from app.models.partner import PartnerApiKey

RAW_KEY = "llk_test_partner_secret"


async def _seed_partner_key(db_session: AsyncSession, raw_key: str = RAW_KEY) -> None:
    db_session.add(
        PartnerApiKey(
            key_id="test-key-01",
            key_hash=hashlib.sha256(raw_key.encode()).hexdigest(),
            owner="test-partner",
            scope="read",
        )
    )
    await db_session.commit()


@pytest.mark.asyncio
async def test_integration_courses_requires_valid_api_key(
    async_client: AsyncClient, db_session: AsyncSession, monkeypatch
):
    get_courses = AsyncMock(return_value=([], 0))
    monkeypatch.setattr(CourseCRUD, "get_courses", get_courses)
    await _seed_partner_key(db_session)

    missing = await async_client.get("/api/v1/integrations/courses")
    invalid = await async_client.get(
        "/api/v1/integrations/courses",
        headers={"X-LexiLingo-API-Key": "wrong"},
    )
    valid = await async_client.get(
        "/api/v1/integrations/courses",
        headers={"X-LexiLingo-API-Key": RAW_KEY},
    )

    assert missing.status_code == 401
    assert missing.json()["error"]["message"] == "Invalid partner API key"
    assert invalid.status_code == 401
    assert invalid.json()["error"]["message"] == "Invalid partner API key"
    assert valid.status_code == 200
    assert valid.json()["data"] == []
    get_courses.assert_awaited_once()


@pytest.mark.asyncio
async def test_integration_revoked_key_is_rejected(
    async_client: AsyncClient, db_session: AsyncSession
):
    db_session.add(
        PartnerApiKey(
            key_id="revoked-key-01",
            key_hash=hashlib.sha256(RAW_KEY.encode()).hexdigest(),
            owner="test-partner",
            scope="read",
            revoked_at=datetime.now(timezone.utc),
        )
    )
    await db_session.commit()

    response = await async_client.get(
        "/api/v1/integrations/courses",
        headers={"X-LexiLingo-API-Key": RAW_KEY},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_integration_expired_key_is_rejected(
    async_client: AsyncClient, db_session: AsyncSession
):
    db_session.add(
        PartnerApiKey(
            key_id="expired-key-01",
            key_hash=hashlib.sha256(RAW_KEY.encode()).hexdigest(),
            owner="test-partner",
            scope="read",
            expires_at=datetime.now(timezone.utc) - timedelta(minutes=1),
        )
    )
    await db_session.commit()

    response = await async_client.get(
        "/api/v1/integrations/courses",
        headers={"X-LexiLingo-API-Key": RAW_KEY},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_integration_openapi_requires_key_and_excludes_other_routes(
    async_client: AsyncClient, db_session: AsyncSession
):
    await _seed_partner_key(db_session)

    missing = await async_client.get("/api/v1/integrations/openapi.json")
    invalid = await async_client.get(
        "/api/v1/integrations/openapi.json",
        headers={"X-LexiLingo-API-Key": "wrong_key"},
    )
    valid = await async_client.get(
        "/api/v1/integrations/openapi.json",
        headers={"X-LexiLingo-API-Key": RAW_KEY},
    )

    assert missing.status_code == 401
    assert invalid.status_code == 401
    assert valid.status_code == 200
    schema = valid.json()
    assert schema["info"]["title"] == "LexiLingo Partner Integrations API"
    assert schema["paths"]
    assert all(path.startswith("/api/v1/integrations/") for path in schema["paths"])
