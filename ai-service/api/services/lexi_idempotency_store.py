"""Redis-backed idempotency store for Lexi chat requests."""

import json
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from fastapi import HTTPException


class LexiIdempotencyStore:
    _PREFIX = "lexi:idempotency:"
    _TTL = timedelta(hours=24)

    def __init__(self):
        self._mem: Dict[str, Dict[str, Any]] = {}

    async def _redis(self):
        try:
            from api.core.redis_client import get_redis
            return await get_redis()
        except Exception:
            return None

    def _key(self, user_id: str, session_id: str, idempotency_key: str) -> str:
        return f"{self._PREFIX}{user_id}:{session_id}:{idempotency_key}"

    def _cleanup_mem(self):
        now = datetime.now(timezone.utc)
        stale = [
            k
            for k, v in self._mem.items()
            if isinstance(v.get("expires_at"), datetime)
            and v.get("expires_at") <= now
        ]
        for k in stale:
            self._mem.pop(k, None)

    async def get(
        self,
        *,
        user_id: str,
        session_id: str,
        idempotency_key: str,
        request_hash: str,
    ) -> Optional[Dict[str, Any]]:
        key = self._key(user_id, session_id, idempotency_key)
        r = await self._redis()
        if r:
            raw = await r.get(key)
            if not raw:
                return None
            data = json.loads(raw)
            if data.get("request_hash") != request_hash:
                raise HTTPException(
                    status_code=409,
                    detail="Idempotency key reused with different payload",
                )
            return data.get("response")

        self._cleanup_mem()
        data = self._mem.get(key)
        if not data:
            return None
        if data.get("request_hash") != request_hash:
            raise HTTPException(
                status_code=409,
                detail="Idempotency key reused with different payload",
            )
        return data.get("response")

    async def set(
        self,
        *,
        user_id: str,
        session_id: str,
        idempotency_key: str,
        request_hash: str,
        response: Dict[str, Any],
    ) -> None:
        key = self._key(user_id, session_id, idempotency_key)
        payload = {"request_hash": request_hash, "response": response}
        r = await self._redis()
        if r:
            await r.set(key, json.dumps(payload), ex=self._TTL)
            return

        self._cleanup_mem()
        self._mem[key] = {
            **payload,
            "expires_at": datetime.now(timezone.utc) + self._TTL,
        }


_idempotency_store: Optional[LexiIdempotencyStore] = None


def get_lexi_idempotency_store() -> LexiIdempotencyStore:
    global _idempotency_store
    if _idempotency_store is None:
        _idempotency_store = LexiIdempotencyStore()
    return _idempotency_store
