"""Tests for Banner — the CEFR-range targeting check, and the public /active route.

Covers:
- _level_in_range: the one non-trivial piece of logic (CEFR comparison with
  open-ended min/max and an unset learner level).
- GET /api/v1/banners/active — public route returns the learner-safe shape
  (no priority/targeting/schedule leaking into BannerPublic).
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock

import pytest
from httpx import ASGITransport, AsyncClient

from app.crud.banner import _level_in_range
from app.models.banner import Banner

BASE = "/api/v1/banners"


class TestLevelInRange:
    def test_no_restriction_always_matches(self):
        assert _level_in_range("A1", None, None) is True
        assert _level_in_range(None, None, None) is True

    def test_unset_level_defaults_to_a1(self):
        assert _level_in_range(None, "A1", "B1") is True
        assert _level_in_range(None, "B1", "C1") is False

    def test_min_level_excludes_below(self):
        assert _level_in_range("A1", "B1", None) is False
        assert _level_in_range("B1", "B1", None) is True

    def test_max_level_excludes_above(self):
        assert _level_in_range("C2", None, "B2") is False
        assert _level_in_range("B2", None, "B2") is True

    def test_case_insensitive(self):
        assert _level_in_range("b1", "A1", "c2") is True


@pytest.fixture
async def public_client():
    from app.main import app
    from app.core.database import get_db

    banner = Banner(
        id=uuid.uuid4(),
        title="New IELTS course",
        description="Launching this week",
        image_url="https://example.com/banner.png",
        link_url="https://example.com/ielts",
        position="hero",
        priority=5,
        is_active=True,
        start_at=None,
        end_at=None,
        target_min_level=None,
        target_max_level=None,
        target_language=None,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )

    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = [banner]
    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    mock_session.execute = fake_execute

    async def mock_get_db():
        yield mock_session

    app.dependency_overrides[get_db] = mock_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


class TestActiveBannerRoute:
    @pytest.mark.asyncio
    async def test_anonymous_sees_untargeted_banner(self, public_client):
        resp = await public_client.get(f"{BASE}/active")
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert len(data) == 1
        assert data[0]["title"] == "New IELTS course"
        # Public shape must not leak admin-only fields.
        assert "priority" not in data[0]
        assert "target_language" not in data[0]
        assert "is_active" not in data[0]
