"""The image proxies serve raster images only: never HTML or SVG from the API's own origin."""
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from httpx import ASGITransport, AsyncClient

from app.core.safe_http import MAX_PROXIED_IMAGE_BYTES, image_proxy_response


def _upstream(content_type, body=b"x"):
    resp = MagicMock()
    resp.status_code = 200
    resp.content = body
    resp.headers = {} if content_type is None else {"content-type": content_type}
    return resp


@pytest.mark.parametrize("ctype", ["text/html", "image/svg+xml", "application/javascript", "text/html; charset=utf-8"])
def test_non_raster_is_refused(ctype):
    with pytest.raises(HTTPException) as err:
        image_proxy_response(_upstream(ctype))
    assert err.value.status_code == 415


def test_oversized_image_is_refused():
    with pytest.raises(HTTPException) as err:
        image_proxy_response(_upstream("image/png", b"0" * (MAX_PROXIED_IMAGE_BYTES + 1)))
    assert err.value.status_code == 413


def test_raster_passes_with_nosniff_and_sandbox():
    out = image_proxy_response(_upstream("image/webp; charset=binary", b"img"))
    assert out.media_type == "image/webp"
    assert out.headers["x-content-type-options"] == "nosniff"
    assert "sandbox" in out.headers["content-security-policy"]


def test_missing_type_is_labelled_jpeg():
    assert image_proxy_response(_upstream(None)).media_type == "image/jpeg"


@pytest.mark.asyncio
async def test_news_proxy_refuses_an_html_page():
    from app.main import app

    with patch("app.routes.news._get_public_url", new=AsyncMock(return_value=_upstream("text/html"))):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            response = await c.get("/api/v1/news/proxy/image", params={"url": "https://example.com/a"})
    assert response.status_code == 415
