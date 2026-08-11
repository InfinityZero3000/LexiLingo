import socket
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.core.logging_config import set_request_id
from app.core.safe_http import resolve_pinned_ip, safe_get


def _addrinfo(ip: str):
    family = socket.AF_INET6 if ":" in ip else socket.AF_INET
    return [(family, socket.SOCK_STREAM, 6, "", (ip, 443))]


def test_resolve_pinned_ip_returns_public_address():
    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        assert resolve_pinned_ip("example.com") == "93.184.216.34"


def test_resolve_pinned_ip_rejects_private_address():
    with patch("socket.getaddrinfo", return_value=_addrinfo("10.0.0.5")):
        with pytest.raises(ValueError):
            resolve_pinned_ip("internal.example")


def test_resolve_pinned_ip_rejects_loopback():
    with patch("socket.getaddrinfo", return_value=_addrinfo("127.0.0.1")):
        with pytest.raises(ValueError):
            resolve_pinned_ip("localhost.example")


@pytest.mark.asyncio
async def test_safe_get_fails_closed_on_dns_error():
    client = MagicMock()
    with patch("socket.getaddrinfo", side_effect=socket.gaierror("no such host")):
        with pytest.raises(HTTPException) as exc_info:
            await safe_get(client, "https://nonexistent.invalid/")
    assert exc_info.value.status_code == 400
    client.get.assert_not_called()


@pytest.mark.asyncio
async def test_safe_get_rejects_private_host_prefix_without_dns_lookup():
    client = MagicMock()
    with patch("socket.getaddrinfo") as mock_resolve:
        with pytest.raises(HTTPException):
            await safe_get(client, "http://localhost:8000/admin")
    mock_resolve.assert_not_called()
    client.get.assert_not_called()


@pytest.mark.asyncio
async def test_safe_get_pins_connection_to_resolved_ip_and_sets_sni():
    client = MagicMock()
    ok_response = MagicMock()
    ok_response.is_redirect = False
    client.get = AsyncMock(return_value=ok_response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        response = await safe_get(client, "https://example.com/article")

    assert response is ok_response
    called_url, kwargs = client.get.call_args
    assert "93.184.216.34" in called_url[0]
    assert "example.com" not in called_url[0]
    assert kwargs["headers"]["Host"] == "example.com"
    assert kwargs["extensions"]["sni_hostname"] == "example.com"
    assert kwargs["follow_redirects"] is False


@pytest.mark.asyncio
async def test_safe_get_propagates_request_id_header():
    client = MagicMock()
    ok_response = MagicMock()
    ok_response.is_redirect = False
    client.get = AsyncMock(return_value=ok_response)

    set_request_id("req-abc-123")
    try:
        with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
            await safe_get(client, "https://example.com/article")
    finally:
        set_request_id("-")

    _, kwargs = client.get.call_args
    assert kwargs["headers"]["X-Request-ID"] == "req-abc-123"


@pytest.mark.asyncio
async def test_safe_get_omits_request_id_header_when_unset():
    client = MagicMock()
    ok_response = MagicMock()
    ok_response.is_redirect = False
    client.get = AsyncMock(return_value=ok_response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        await safe_get(client, "https://example.com/article")

    _, kwargs = client.get.call_args
    assert "X-Request-ID" not in kwargs["headers"]


@pytest.mark.asyncio
async def test_safe_get_revalidates_on_redirect_to_private_target():
    client = MagicMock()
    redirect_response = MagicMock()
    redirect_response.is_redirect = True
    redirect_response.headers = {"location": "http://169.254.169.254/latest/meta-data/"}
    client.get = AsyncMock(return_value=redirect_response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        with pytest.raises(HTTPException):
            await safe_get(client, "https://example.com/redirects-to-metadata")


@pytest.mark.asyncio
async def test_safe_get_caps_redirect_count():
    client = MagicMock()
    redirect_response = MagicMock()
    redirect_response.is_redirect = True
    redirect_response.headers = {"location": "https://example.com/next"}
    client.get = AsyncMock(return_value=redirect_response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        with pytest.raises(HTTPException) as exc_info:
            await safe_get(client, "https://example.com/loop", max_redirects=2)
    assert "redirects" in exc_info.value.detail.lower()


@pytest.mark.network
@pytest.mark.asyncio
async def test_safe_get_live_fetch_real_site():
    """Live smoke test: pinned connection must return the same content a
    normal request would. Skipped automatically if there's no network."""
    import httpx

    try:
        socket.getaddrinfo("example.com", None)
    except OSError:
        pytest.skip("no network access in this environment")

    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await safe_get(client, "https://example.com/")
    assert response.status_code == 200
    assert b"Example Domain" in response.content
