"""Server-side cache for proxied upstream bodies (covers, book texts).

Entries are only written after the fetch succeeded and the body passed its
validation, and callers must validate the URL *before* reading the cache, so a
cache entry can never be a way to serve a URL the proxy would refuse.
"""

from __future__ import annotations

import base64
import hashlib
from typing import Optional

from fastapi import Response

from app.core.cache import get_cached, set_cached
from app.core.safe_http import (
    IMAGE_PROXY_HEADERS,
    MAX_PROXIED_IMAGE_BYTES,
    PROXIED_IMAGE_TYPES,
)

PROXY_CACHE_TTL_SECONDS = 7 * 24 * 3600
MAX_CACHED_TEXT_BYTES = 2 * 1024 * 1024


def proxy_cache_key(kind: str, url: str) -> str:
    return f"proxy:{kind}:v1:{hashlib.sha256(url.encode()).hexdigest()}"


async def get_cached_body(
    kind: str, url: str, headers: dict[str, str]
) -> Optional[Response]:
    entry = await get_cached(proxy_cache_key(kind, url))
    if not isinstance(entry, dict):
        return None
    try:
        body = base64.b64decode(entry["b"], validate=True)
        media = str(entry["m"])
    except Exception:
        return None
    return Response(content=body, media_type=media, headers=dict(headers))


async def put_cached_body(
    kind: str, url: str, response: Response, *, max_bytes: int
) -> None:
    body = bytes(response.body)
    if not body or len(body) > max_bytes or not response.media_type:
        return
    await set_cached(
        proxy_cache_key(kind, url),
        {"m": response.media_type, "b": base64.b64encode(body).decode("ascii")},
        ttl=PROXY_CACHE_TTL_SECONDS,
    )


async def get_cached_image(url: str) -> Optional[Response]:
    entry = await get_cached_body("img", url, IMAGE_PROXY_HEADERS)
    if entry is None or entry.media_type not in PROXIED_IMAGE_TYPES:
        return None
    return entry


async def put_cached_image(url: str, response: Response) -> None:
    await put_cached_body("img", url, response, max_bytes=MAX_PROXIED_IMAGE_BYTES)
