"""Topic Chat Repository — all MongoDB I/O for chat_sessions and chat_messages."""

import logging
from typing import Any

from motor.motor_asyncio import AsyncIOMotorDatabase

from api.utils.cursor import decode_cursor_dt, load_full_cursor

logger = logging.getLogger(__name__)


class TopicChatRepository:
    def __init__(self, db: AsyncIOMotorDatabase) -> None:
        self._sessions = db["chat_sessions"]
        self._messages = db["chat_messages"]

    # ── sessions ────────────────────────────────────────────────────────────

    async def get_session(self, session_id: str) -> dict | None:
        return await self._sessions.find_one({"session_id": session_id})

    async def create_session(self, session: dict) -> None:
        await self._sessions.insert_one(session)

    async def update_session_kg(
        self, session_id: str, kg_seeds: list, topic_fingerprint: str
    ) -> None:
        await self._sessions.update_one(
            {"session_id": session_id},
            {"$set": {
                "kg_seed_concepts": kg_seeds,
                "kg_topic_fingerprint": topic_fingerprint,
            }},
        )

    # ── messages ────────────────────────────────────────────────────────────

    async def insert_message(self, message: dict) -> None:
        await self._messages.insert_one(message)

    async def get_history(self, session_id: str, limit: int = 10) -> list[dict]:
        """Return the most recent `limit` messages in ascending order."""
        docs = (
            await self._messages.find({"session_id": session_id})
            .sort("timestamp", -1)
            .limit(limit)
            .to_list(length=limit)
        )
        docs.reverse()
        return docs

    async def get_messages(self, session_id: str, limit: int = 0) -> list[dict]:
        """Return messages in ascending order; limit=0 means fetch all."""
        cursor = self._messages.find({"session_id": session_id}).sort("timestamp", 1)
        if limit > 0:
            return await cursor.limit(limit).to_list(length=limit)
        return await load_full_cursor(cursor)

    async def count_messages(self, session_id: str) -> int:
        return await self._messages.count_documents({"session_id": session_id})

    async def get_messages_paged(
        self,
        session_id: str,
        limit: int,
        cursor: str | None = None,
    ) -> tuple[list[dict], bool]:
        """Return (docs_asc, has_more) for cursor-paginated listing."""
        safe_limit = min(limit, 200)
        base_query: dict[str, Any] = {"session_id": session_id}
        query: dict[str, Any] = dict(base_query)

        if cursor:
            cursor_ts, cursor_oid = decode_cursor_dt(cursor)
            query = {
                "session_id": session_id,
                "$or": [
                    {"timestamp": {"$lt": cursor_ts}},
                    {"timestamp": cursor_ts, "_id": {"$lt": cursor_oid}},
                ],
            }

        docs_desc = await (
            self._messages.find(query)
            .sort([("timestamp", -1), ("_id", -1)])
            .limit(safe_limit + 1)
            .to_list(length=safe_limit + 1)
        )
        has_more = len(docs_desc) > safe_limit
        docs_desc = docs_desc[:safe_limit]
        return list(reversed(docs_desc)), has_more

    async def get_latest_message(self, session_id: str) -> dict | None:
        docs = await (
            self._messages.find({"session_id": session_id})
            .sort([("timestamp", -1), ("_id", -1)])
            .limit(1)
            .to_list(length=1)
        )
        return docs[0] if docs else None

    async def get_oldest_message(self, session_id: str) -> dict | None:
        docs = await (
            self._messages.find({"session_id": session_id})
            .sort([("timestamp", 1), ("_id", 1)])
            .limit(1)
            .to_list(length=1)
        )
        return docs[0] if docs else None

    async def insert_messages_bulk(self, messages: list[dict]) -> None:
        if messages:
            await self._messages.insert_many(messages)

    async def update_session_activity(
        self,
        session_id: str,
        last_activity,
        message_count_increment: int = 2,
    ) -> None:
        await self._sessions.update_one(
            {"session_id": session_id},
            {
                "$set": {"last_activity": last_activity},
                "$inc": {"message_count": message_count_increment},
            },
        )
