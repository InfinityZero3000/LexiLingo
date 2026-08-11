"""Centralized SSRF-safe outbound HTTP fetching for user/partner-supplied URLs.

Used by routes that fetch content from a URL the caller controls (news
article scraping, podcast RSS/image proxying, ...). Two properties matter
here, both from the backend audit's SSRF finding:

1. Fail closed. A hostname that doesn't resolve, or resolves to nothing
   public, is rejected — never silently allowed through on the assumption
   "httpx will handle it".
2. No check-then-use gap. Validating a hostname's resolved IP and then
   handing the *hostname* to httpx for the real connection leaves a window
   for DNS rebinding: the validation's DNS answer and the connection's DNS
   answer are two independent lookups and can differ. This module resolves
   once, verifies the address is public, and pins the actual TCP connection
   to that address — passing the original hostname via the Host header and
   TLS SNI (extensions={"sni_hostname": ...}) so certificate verification
   still matches the real domain. Every redirect hop repeats this from
   scratch against the redirect target.
"""

from __future__ import annotations

import socket
from collections.abc import Collection
from ipaddress import ip_address
from urllib.parse import urljoin, urlparse, urlunparse

import anyio
import httpx
from fastapi import HTTPException, status

from app.core.logging_config import get_request_id

_PRIVATE_HOST_PREFIXES = (
    "localhost", "127.", "0.0.0.0", "10.", "192.168.", "172.16.",
    "172.17.", "172.18.", "172.19.", "172.20.", "172.21.",
    "172.22.", "172.23.", "172.24.", "172.25.", "172.26.",
    "172.27.", "172.28.", "172.29.", "172.30.", "172.31.",
    "169.254.", "fc00", "fd", "fe80",
)

_REJECTED = HTTPException(
    status_code=status.HTTP_400_BAD_REQUEST,
    detail="Only public HTTP/HTTPS URLs are allowed.",
)
MAX_RESPONSE_BYTES = 10 * 1024 * 1024


def resolve_pinned_ip(host: str) -> str:
    """Resolve *host* and return its first publicly-routable address.

    Raises ValueError (caller should treat as reject, not skip) if the host
    doesn't resolve or every resolved address is private/loopback/link-local.
    """
    infos = socket.getaddrinfo(host, None, socket.AF_UNSPEC, socket.SOCK_STREAM)
    for info in infos:
        candidate = info[4][0]
        parsed = ip_address(candidate)
        # is_global alone still admits multicast ranges (224.0.0.0/4, ff00::/8).
        if parsed.is_global and not parsed.is_multicast:
            return candidate
    raise ValueError(f"No public address resolved for host: {host}")


def _pin_url(url: str, pinned_ip: str) -> str:
    parsed = urlparse(url)
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    netloc = f"[{pinned_ip}]:{port}" if ":" in pinned_ip else f"{pinned_ip}:{port}"
    return urlunparse(parsed._replace(netloc=netloc))


def validate_public_url(
    url: str,
    *,
    allowed_hosts: Collection[str] | None = None,
) -> None:
    """Reject malformed, non-HTTP, private, and non-allowlisted URLs."""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise _REJECTED
    host = parsed.hostname.lower()
    if allowed_hosts is not None and host not in allowed_hosts:
        raise _REJECTED
    if any(host == prefix or host.startswith(prefix) for prefix in _PRIVATE_HOST_PREFIXES):
        raise _REJECTED


async def _validate_and_pin(
    current_url: str,
    kwargs: dict,
    allowed_hosts: Collection[str] | None = None,
) -> tuple[str, dict]:
    """Validate current_url and return (pinned_url, request_kwargs)."""
    validate_public_url(current_url, allowed_hosts=allowed_hosts)
    parsed = urlparse(current_url)
    host = parsed.hostname.lower()
    try:
        pinned_ip = await anyio.to_thread.run_sync(resolve_pinned_ip, host)
    except (socket.gaierror, ValueError) as exc:
        raise _REJECTED from exc

    headers = dict(kwargs.get("headers") or {})
    headers.setdefault("Host", host)
    request_id = get_request_id()
    if request_id != "-":
        headers.setdefault("X-Request-ID", request_id)
    extensions = dict(kwargs.get("extensions") or {})
    if parsed.scheme == "https":
        extensions.setdefault("sni_hostname", host)

    request_kwargs = {**kwargs, "headers": headers, "extensions": extensions}
    return _pin_url(current_url, pinned_ip), request_kwargs


async def safe_get(
    client: httpx.AsyncClient,
    url: str,
    *,
    max_redirects: int = 5,
    max_response_bytes: int = MAX_RESPONSE_BYTES,
    allowed_hosts: Collection[str] | None = None,
    **kwargs,
) -> httpx.Response:
    """GET *url* with validated redirects and a bounded, buffered body."""
    response = await safe_stream_get(
        client,
        url,
        max_redirects=max_redirects,
        allowed_hosts=allowed_hosts,
        **kwargs,
    )
    try:
        content_length = response.headers.get("content-length")
        if (
            content_length
            and content_length.isdigit()
            and int(content_length) > max_response_bytes
        ):
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail="Response exceeds the size limit.",
            )

        content = bytearray()
        async for chunk in response.aiter_bytes():
            content.extend(chunk)
            if len(content) > max_response_bytes:
                raise HTTPException(
                    status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                    detail="Response exceeds the size limit.",
                )
        response._content = bytes(content)
        return response
    finally:
        await response.aclose()


async def safe_stream_get(
    client: httpx.AsyncClient,
    url: str,
    *,
    max_redirects: int = 5,
    allowed_hosts: Collection[str] | None = None,
    **kwargs,
) -> httpx.Response:
    """Like safe_get, but opens a streaming response (client.send(stream=True))
    instead of buffering the body — callers must consume response.aiter_bytes()
    and call response.aclose() themselves (a `finally` block)."""
    current_url = url
    for _ in range(max_redirects + 1):
        pinned_url, request_kwargs = await _validate_and_pin(
            current_url, kwargs, allowed_hosts
        )
        request = client.build_request("GET", pinned_url, **request_kwargs)
        response = await client.send(request, stream=True)
        if response.is_redirect and response.headers.get("location"):
            current_url = urljoin(current_url, response.headers["location"])
            await response.aclose()
            continue
        return response
    raise HTTPException(status_code=400, detail="Too many redirects.")
