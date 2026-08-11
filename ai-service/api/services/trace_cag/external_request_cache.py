"""Short-lived idempotency cache that stores no learner request data.

Backed by Redis (not an in-memory dict) so entries actually expire — an
in-memory dict only drops an entry when someone happens to re-fetch it
after its TTL, so a request_id used exactly once (the common case for an
idempotency key) never gets cleaned up and leaks memory for the life of
the process — and so idempotency holds across multiple workers/replicas,
not just within one.
"""

from __future__ import annotations

import json
from typing import Any


class ExternalRequestCache:
    def __init__(self, ttl_seconds: int = 600) -> None:
        self.ttl_seconds = ttl_seconds

    @staticmethod
    def _key(request_id: str) -> str:
        return f"external_request:{request_id}"

    async def get(self, request_id: str, fingerprint: str) -> tuple[str, dict[str, Any] | None]:
        from api.core.redis_client import RedisClient

        raw = await RedisClient.execute_with_reconnect(
            lambda r: r.get(self._key(request_id))
        )
        if raw is None:
            return "miss", None
        entry = json.loads(raw)
        if entry["fingerprint"] != fingerprint:
            return "conflict", None
        return "hit", entry["response"]

    async def put(self, request_id: str, fingerprint: str, response: dict[str, Any]) -> None:
        from api.core.redis_client import RedisClient

        payload = json.dumps({"fingerprint": fingerprint, "response": response})
        await RedisClient.execute_with_reconnect(
            lambda r: r.set(self._key(request_id), payload, ex=self.ttl_seconds)
        )
