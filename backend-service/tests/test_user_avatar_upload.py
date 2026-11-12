"""POST /api/v1/users/me/avatar — files are written for real, the DB session is faked."""

import uuid
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock

import pytest
from httpx import ASGITransport, AsyncClient

from app.routes import users as users_routes

URL = "/api/v1/users/me/avatar"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
WEBP = b"RIFF\x00\x00\x00\x00WEBP" + b"\x00" * 64


def _user():
    user = MagicMock()
    user.id = uuid.UUID("550e8400-e29b-41d4-a716-446655440001")
    user.email, user.username, user.display_name = "tester@example.com", "tester", "Tester"
    user.is_active = user.is_verified = True
    user.level = user.cefr_level = "A1"
    user.goal = user.interest = user.avatar_url = user.last_login = user.role_id = None
    user.native_language, user.target_language = "vi", "en"
    user.total_xp, user.numeric_level, user.rank = 0, 1, "bronze"
    user.created_at = datetime.now(UTC)
    user.role_slug, user.role_level = "user", 0
    return user


@pytest.fixture
async def client(tmp_path, monkeypatch):
    from app.core.database import get_db
    from app.core.dependencies import get_current_user
    from app.main import app

    monkeypatch.setattr(users_routes, "_AVATAR_MEDIA_DIR", tmp_path)
    monkeypatch.setattr(users_routes.settings, "MEDIA_PUBLIC_BASE_URL", "https://api.example.test")
    session = MagicMock(commit=AsyncMock(), refresh=AsyncMock())
    user = _user()

    async def fake_db():
        yield session

    app.dependency_overrides[get_db] = fake_db
    app.dependency_overrides[get_current_user] = lambda: user
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        c.media, c.user, c.session = tmp_path, user, session
        yield c
    app.dependency_overrides.clear()


def _post(client, body: bytes, name="me.png", ctype="image/png"):
    return client.post(URL, files={"file": (name, body, ctype)})


@pytest.mark.parametrize("body,ext", [(PNG, ".png"), (JPEG, ".jpg"), (WEBP, ".webp")], ids=["png", "jpeg", "webp"])
async def test_valid_image_is_stored_and_saved_on_user(client, body, ext):
    resp = await _post(client, body)
    assert resp.status_code == 200, resp.text
    url = resp.json()["avatar_url"]
    assert url.startswith(f"https://api.example.test/media/avatars/{client.user.id}-")
    assert url.endswith(ext)
    assert client.user.avatar_url == url
    assert (client.media / "avatars" / url.rsplit("/", 1)[1]).read_bytes() == body
    client.session.commit.assert_awaited()


async def test_new_upload_replaces_the_old_file(client):
    first = (await _post(client, PNG)).json()["avatar_url"]
    second = (await _post(client, JPEG, "me.jpg", "image/jpeg")).json()["avatar_url"]
    assert {p.name for p in (client.media / "avatars").iterdir()} == {second.rsplit("/", 1)[1]}
    assert first != second


async def test_extension_and_content_type_are_not_trusted(client):
    resp = await _post(client, b"<html>not an image</html>", "evil.png", "image/png")
    assert resp.status_code == 400
    assert not (client.media / "avatars").exists()
    assert client.user.avatar_url is None


async def test_svg_is_refused(client):
    svg = b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
    assert (await _post(client, svg, "a.svg", "image/svg+xml")).status_code == 400


async def test_oversized_file_is_refused(client):
    resp = await _post(client, PNG + b"\x00" * (2 * 1024 * 1024))
    assert resp.status_code == 413
    assert not (client.media / "avatars").exists()


async def test_requires_authentication():
    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        resp = await c.post(URL, files={"file": ("me.png", PNG, "image/png")})
    assert resp.status_code in (401, 403)
