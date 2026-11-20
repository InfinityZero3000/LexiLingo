"""POST /api/v1/admin/upload/banner — files are written for real into tmp_path, the DB is faked."""

import re
import uuid
from unittest.mock import AsyncMock, MagicMock

import pytest
from httpx import ASGITransport, AsyncClient

from app.routes import admin_courses

BANNER = "/api/v1/admin/upload/banner"
BADGE = "/api/v1/admin/upload/badge"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


def _admin():
    user = MagicMock()
    user.id = uuid.UUID("550e8400-e29b-41d4-a716-446655440002")
    user.role_id = uuid.uuid4()
    user.role_level = 1
    return user


def _make_client(tmp_path, monkeypatch, has_permission: bool):
    from app.core.database import get_db
    from app.core.dependencies import get_current_user
    from app.main import app

    monkeypatch.setattr(admin_courses, "_MEDIA_DIR", tmp_path)
    monkeypatch.setattr(admin_courses.settings, "MEDIA_PUBLIC_BASE_URL", "https://api.example.test")
    result = MagicMock(first=MagicMock(return_value=("banners:create",) if has_permission else None))
    session = MagicMock(execute=AsyncMock(return_value=result))

    async def fake_db():
        yield session

    app.dependency_overrides[get_db] = fake_db
    app.dependency_overrides[get_current_user] = _admin
    return app


@pytest.fixture
async def client(tmp_path, monkeypatch):
    app = _make_client(tmp_path, monkeypatch, has_permission=True)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
async def unprivileged_client(tmp_path, monkeypatch):
    app = _make_client(tmp_path, monkeypatch, has_permission=False)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


def _post(client, url, body=PNG, name="hero.png", ctype="image/png"):
    return client.post(url, files={"file": (name, body, ctype)})


async def test_valid_png_returns_absolute_url_and_writes_file(client, tmp_path):
    resp = await _post(client, BANNER)
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert re.fullmatch(r"https://api\.example\.test/media/banners/[0-9a-f]{32}\.png", data["url"])
    assert (tmp_path / "banners" / data["filename"]).read_bytes() == PNG


async def test_origin_falls_back_to_request_base_url(client, monkeypatch):
    monkeypatch.setattr(admin_courses.settings, "MEDIA_PUBLIC_BASE_URL", "")
    resp = await _post(client, BANNER)
    assert resp.json()["data"]["url"].startswith("http://test/media/banners/")


async def test_svg_rejected(client, tmp_path):
    resp = await _post(client, BANNER, b"<svg/>", "x.svg", "image/svg+xml")
    assert resp.status_code == 400
    assert not (tmp_path / "banners").exists()


async def test_oversize_rejected(client, tmp_path):
    resp = await _post(client, BANNER, PNG + b"\x00" * (2 * 1024 * 1024))
    assert resp.status_code == 400
    assert not (tmp_path / "banners").exists()


async def test_user_without_banners_permission_gets_403(unprivileged_client, tmp_path):
    resp = await _post(unprivileged_client, BANNER)
    assert resp.status_code == 403
    assert not (tmp_path / "banners").exists()


async def test_badge_upload_still_returns_relative_url(client, tmp_path):
    resp = await _post(client, BADGE)
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert re.fullmatch(r"/media/badges/[0-9a-f]{32}\.png", data["url"])
    assert (tmp_path / "badges" / data["filename"]).exists()
