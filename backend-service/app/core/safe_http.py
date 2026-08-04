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
from ipaddress import ip_address
from urllib.parse import urljoin, urlparse, urlunparse

import httpx
from fastapi import HTTPException, status

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


def resolve_pinned_ip(host: str) -> str:
    """Resolve *host* and return its first publicly-routable address.

    Raises ValueError (caller should treat as reject, not skip) if the host
    doesn't resolve or every resolved address is private/loopback/link-local.
    """
    infos = socket.getaddrinfo(host, None, socket.AF_UNSPEC, socket.SOCK_STREAM)
    for info in infos:
        candidate = info[4][0]
        parsed = ip_address(candidate)
        if not (
            parsed.is_private
            or parsed.is_loopback
            or parsed.is_link_local
            or parsed.is_reserved
            or parsed.is_multicast
            or parsed.is_unspecified
        ):
            return candidate
    raise ValueError(f"No public address resolved for host: {host}")


def _pin_url(url: str, pinned_ip: str) -> str:
    parsed = urlparse(url)
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    netloc = f"[{pinned_ip}]:{port}" if ":" in pinned_ip else f"{pinned_ip}:{port}"
    return urlunparse(parsed._replace(netloc=netloc))


async def safe_get(
    client: httpx.AsyncClient,
    url: str,
    *,
    max_redirects: int = 5,
    **kwargs,
) -> httpx.Response:
    """GET *url*, validating and IP-pinning every hop (including redirects)."""
    current_url = url
    for _ in range(max_redirects + 1):
        parsed = urlparse(current_url)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            raise _REJECTED
        host = parsed.hostname.lower()
        if any(host == prefix or host.startswith(prefix) for prefix in _PRIVATE_HOST_PREFIXES):
            raise _REJECTED
        try:
            pinned_ip = resolve_pinned_ip(host)
        except (socket.gaierror, ValueError) as exc:
            raise _REJECTED from exc

        headers = dict(kwargs.pop("headers", None) or {})
        headers.setdefault("Host", host)
        extensions = dict(kwargs.pop("extensions", None) or {})
        if parsed.scheme == "https":
            extensions.setdefault("sni_hostname", host)

        response = await client.get(
            _pin_url(current_url, pinned_ip),
            headers=headers,
            extensions=extensions,
            follow_redirects=False,
            **kwargs,
        )
        if response.is_redirect and response.headers.get("location"):
            current_url = urljoin(current_url, response.headers["location"])
            continue
        return response
    raise HTTPException(status_code=400, detail="Too many redirects.")
