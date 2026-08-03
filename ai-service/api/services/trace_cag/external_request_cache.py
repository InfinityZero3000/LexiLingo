"""Short-lived idempotency cache that stores no learner request data."""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass
from typing import Any


@dataclass(slots=True)
class _Entry:
    fingerprint: str
    response: dict[str, Any]
    expires_at: float


class ExternalRequestCache:
    def __init__(self, ttl_seconds: int = 600) -> None:
        self.ttl_seconds = ttl_seconds
        self._entries: dict[str, _Entry] = {}
        self._lock = asyncio.Lock()

    async def get(self, request_id: str, fingerprint: str) -> tuple[str, dict[str, Any] | None]:
        async with self._lock:
            entry = self._entries.get(request_id)
            if not entry or entry.expires_at <= time.monotonic():
                self._entries.pop(request_id, None)
                return "miss", None
            if entry.fingerprint != fingerprint:
                return "conflict", None
            return "hit", dict(entry.response)

    async def put(self, request_id: str, fingerprint: str, response: dict[str, Any]) -> None:
        async with self._lock:
            self._entries[request_id] = _Entry(
                fingerprint=fingerprint,
                response=dict(response),
                expires_at=time.monotonic() + self.ttl_seconds,
            )
