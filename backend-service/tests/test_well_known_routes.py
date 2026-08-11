"""Route coverage for app/universal link metadata."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_well_known_routes_are_mounted():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        assetlinks = await client.get("/.well-known/assetlinks.json")
        aasa = await client.get("/.well-known/apple-app-site-association")

    assert assetlinks.status_code == 200
    assert assetlinks.json()[0]["target"]["namespace"] == "android_app"
    assert aasa.status_code == 200
    assert "applinks" in aasa.json()
