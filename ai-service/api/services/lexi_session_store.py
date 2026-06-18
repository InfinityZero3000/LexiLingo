"""Redis-backed Lexi session + message store with in-memory fallback."""

import json
from datetime import timedelta
from typing import Any, Dict, List, Optional


class LexiSessionStore:
    """
    Persists Lexi sessions & messages in Redis.
    Falls back to in-memory dicts when Redis is unavailable so the
    chat endpoint still works during local dev without Redis.
    """

    _SESSION_PREFIX = "lexi:session:"
    _MSG_PREFIX = "lexi:msgs:"
    _TTL = timedelta(hours=24)

    def __init__(self):
        self._mem_sessions: Dict[str, Dict[str, Any]] = {}
        self._mem_messages: Dict[str, List[Dict[str, Any]]] = {}

    async def _redis(self):
        try:
            from api.core.redis_client import get_redis
            return await get_redis()
        except Exception:
            return None

    async def get_session(self, sid: str) -> Optional[Dict[str, Any]]:
        r = await self._redis()
        if r:
            raw = await r.get(f"{self._SESSION_PREFIX}{sid}")
            if raw:
                return json.loads(raw)
            return None
        return self._mem_sessions.get(sid)

    async def set_session(self, sid: str, data: Dict[str, Any]):
        r = await self._redis()
        if r:
            await r.set(
                f"{self._SESSION_PREFIX}{sid}",
                json.dumps(data),
                ex=self._TTL,
            )
        else:
            self._mem_sessions[sid] = data

    async def has_session(self, sid: str) -> bool:
        return (await self.get_session(sid)) is not None

    async def get_messages(self, sid: str) -> List[Dict[str, Any]]:
        r = await self._redis()
        if r:
            raw_list = await r.lrange(f"{self._MSG_PREFIX}{sid}", 0, -1)
            return [json.loads(m) for m in raw_list] if raw_list else []
        return self._mem_messages.get(sid, [])

    async def get_session_with_messages(
        self,
        sid: str,
    ) -> tuple[Optional[Dict[str, Any]], List[Dict[str, Any]]]:
        r = await self._redis()
        if r:
            pipe = r.pipeline(transaction=False)
            pipe.get(f"{self._SESSION_PREFIX}{sid}")
            pipe.lrange(f"{self._MSG_PREFIX}{sid}", 0, -1)
            raw_session, raw_messages = await pipe.execute()
            session = json.loads(raw_session) if raw_session else None
            messages = [json.loads(m) for m in raw_messages] if raw_messages else []
            return session, messages

        return self._mem_sessions.get(sid), self._mem_messages.get(sid, [])

    async def append_message(self, sid: str, msg: Dict[str, Any]):
        r = await self._redis()
        if r:
            key = f"{self._MSG_PREFIX}{sid}"
            await r.rpush(key, json.dumps(msg))
            await r.expire(key, self._TTL)
        else:
            self._mem_messages.setdefault(sid, []).append(msg)

    async def append_messages(self, sid: str, messages: List[Dict[str, Any]]):
        messages = list(messages)
        if not messages:
            return

        r = await self._redis()
        if r:
            key = f"{self._MSG_PREFIX}{sid}"
            pipe = r.pipeline(transaction=False)
            pipe.rpush(key, *[json.dumps(msg) for msg in messages])
            pipe.expire(key, self._TTL)
            await pipe.execute()
        else:
            self._mem_messages.setdefault(sid, []).extend(messages)

    async def init_messages(self, sid: str):
        """Ensure the message list exists (no-op for Redis, inits list for mem)."""
        self._mem_messages.setdefault(sid, [])

    async def delete_session(self, sid: str):
        r = await self._redis()
        if r:
            await r.delete(f"{self._SESSION_PREFIX}{sid}")
        self._mem_sessions.pop(sid, None)

    async def delete_messages(self, sid: str):
        r = await self._redis()
        if r:
            await r.delete(f"{self._MSG_PREFIX}{sid}")
        self._mem_messages.pop(sid, None)


_store: Optional[LexiSessionStore] = None


def get_lexi_store() -> LexiSessionStore:
    global _store
    if _store is None:
        _store = LexiSessionStore()
    return _store
