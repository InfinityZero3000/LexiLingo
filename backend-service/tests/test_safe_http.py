import socket
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi import HTTPException

from app.core.logging_config import set_request_id
from app.core.safe_http import MAX_RESPONSE_BYTES, resolve_pinned_ip, safe_get


def _addrinfo(ip: str):
    family = socket.AF_INET6 if ":" in ip else socket.AF_INET
    return [(family, socket.SOCK_STREAM, 6, "", (ip, 443))]


def _client_for(response: httpx.Response) -> MagicMock:
    client = MagicMock()
    client.build_request.return_value = response.request
    client.send = AsyncMock(return_value=response)
    return client


class _ChunkedStream(httpx.AsyncByteStream):
    async def __aiter__(self):
        yield b"12345"
        yield b"6"


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
    request = httpx.Request("GET", "https://93.184.216.34/article")
    ok_response = httpx.Response(200, content=b"ok", request=request)
    client = _client_for(ok_response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        response = await safe_get(client, "https://example.com/article")

    assert response is ok_response
    method, called_url = client.build_request.call_args.args
    kwargs = client.build_request.call_args.kwargs
    assert method == "GET"
    assert "93.184.216.34" in called_url
    assert "example.com" not in called_url
    assert kwargs["headers"]["Host"] == "example.com"
    assert kwargs["extensions"]["sni_hostname"] == "example.com"
    client.send.assert_awaited_once_with(request, stream=True)


@pytest.mark.asyncio
async def test_safe_get_propagates_request_id_header():
    request = httpx.Request("GET", "https://93.184.216.34/article")
    client = _client_for(httpx.Response(200, content=b"ok", request=request))

    set_request_id("req-abc-123")
    try:
        with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
            await safe_get(client, "https://example.com/article")
    finally:
        set_request_id("-")

    kwargs = client.build_request.call_args.kwargs
    assert kwargs["headers"]["X-Request-ID"] == "req-abc-123"


@pytest.mark.asyncio
async def test_safe_get_omits_request_id_header_when_unset():
    request = httpx.Request("GET", "https://93.184.216.34/article")
    client = _client_for(httpx.Response(200, content=b"ok", request=request))

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        await safe_get(client, "https://example.com/article")

    kwargs = client.build_request.call_args.kwargs
    assert "X-Request-ID" not in kwargs["headers"]


@pytest.mark.asyncio
async def test_safe_get_revalidates_on_redirect_to_private_target():
    request = httpx.Request("GET", "https://93.184.216.34/redirect")
    redirect_response = httpx.Response(
        302,
        headers={"location": "http://169.254.169.254/latest/meta-data/"},
        request=request,
    )
    client = _client_for(redirect_response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        with pytest.raises(HTTPException):
            await safe_get(client, "https://example.com/redirects-to-metadata")


@pytest.mark.asyncio
async def test_safe_get_caps_redirect_count():
    request = httpx.Request("GET", "https://93.184.216.34/loop")
    redirect_response = httpx.Response(
        302,
        headers={"location": "https://example.com/next"},
        request=request,
    )
    client = _client_for(redirect_response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        with pytest.raises(HTTPException) as exc_info:
            await safe_get(client, "https://example.com/loop", max_redirects=2)
    assert "redirects" in exc_info.value.detail.lower()


@pytest.mark.asyncio
async def test_safe_get_revalidates_redirect_against_allowlist():
    request = httpx.Request("GET", "https://93.184.216.34/redirect")
    client = _client_for(
        httpx.Response(
            302,
            headers={"location": "https://evil.example/payload"},
            request=request,
        )
    )

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        with pytest.raises(HTTPException) as exc_info:
            await safe_get(
                client,
                "https://example.com/redirect",
                allowed_hosts={"example.com"},
            )

    assert exc_info.value.status_code == 400
    assert client.send.await_count == 1


@pytest.mark.asyncio
async def test_safe_get_rejects_oversized_content_length_before_reading():
    request = httpx.Request("GET", "https://93.184.216.34/large")
    client = _client_for(
        httpx.Response(
            200,
            headers={"content-length": str(MAX_RESPONSE_BYTES + 1)},
            content=b"ignored",
            request=request,
        )
    )

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        with pytest.raises(HTTPException) as exc_info:
            await safe_get(client, "https://example.com/large")

    assert exc_info.value.status_code == 413


@pytest.mark.asyncio
async def test_safe_get_aborts_stream_when_body_exceeds_limit():
    request = httpx.Request("GET", "https://93.184.216.34/chunked")
    response = httpx.Response(200, stream=_ChunkedStream(), request=request)
    client = _client_for(response)

    with patch("socket.getaddrinfo", return_value=_addrinfo("93.184.216.34")):
        with pytest.raises(HTTPException) as exc_info:
            await safe_get(client, "https://example.com/chunked", max_response_bytes=5)

    assert exc_info.value.status_code == 413
    assert response.is_closed


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
