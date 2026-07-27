import hashlib
from unittest.mock import AsyncMock

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import settings
from app.crud.course import CourseCRUD
from app.main import app


@pytest.mark.asyncio
async def test_integration_courses_requires_valid_api_key(monkeypatch):
    raw_key = "llk_test_partner_secret"
    get_courses = AsyncMock(return_value=([], 0))
    monkeypatch.setattr(
        settings,
        "LEXILINGO_PARTNER_API_KEY_HASHES",
        hashlib.sha256(raw_key.encode()).hexdigest(),
        raising=False,
    )
    monkeypatch.setattr(CourseCRUD, "get_courses", get_courses)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        missing = await client.get("/api/v1/integrations/courses")
        invalid = await client.get(
            "/api/v1/integrations/courses",
            headers={"X-LexiLingo-API-Key": "wrong"},
        )
        valid = await client.get(
            "/api/v1/integrations/courses",
            headers={"X-LexiLingo-API-Key": raw_key},
        )

    assert missing.status_code == 401
    assert missing.json()["error"]["message"] == "Invalid partner API key"
    assert invalid.status_code == 401
    assert invalid.json()["error"]["message"] == "Invalid partner API key"
    assert valid.status_code == 200
    assert valid.json()["data"] == []
    get_courses.assert_awaited_once()
