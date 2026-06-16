"""Shared cursor-based pagination utilities for MongoDB collections.

Two decode variants exist because different collections store the timestamp field
with different types: lexi_messages uses ISO strings, chat_messages/topic_chat_messages
use native datetime objects.
"""

from __future__ import annotations

import base64
import json
from datetime import datetime
from typing import Any

from bson import ObjectId
from fastapi import HTTPException


async def load_full_cursor(cursor: Any, batch_size: int = 500) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    while True:
        batch = await cursor.to_list(length=batch_size)
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < batch_size:
            break
    return rows


def to_iso_timestamp(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def encode_cursor(doc: dict[str, Any]) -> str:
    ts = to_iso_timestamp(doc.get("timestamp"))
    oid = str(doc.get("_id", ""))
    payload = json.dumps({"ts": ts, "oid": oid}, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(payload).decode("utf-8")


def decode_cursor_dt(cursor: str) -> tuple[datetime, ObjectId]:
    """Decode a cursor token to (datetime, ObjectId).

    Used by collections that store timestamps as native datetime objects
    (chat_messages, topic chat messages).
    """
    try:
        padding = "=" * (-len(cursor) % 4)
        raw = base64.urlsafe_b64decode(f"{cursor}{padding}".encode("utf-8"))
        data = json.loads(raw.decode("utf-8"))
        ts_raw = str(data["ts"])
        ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
        if ts.tzinfo is not None:
            ts = ts.astimezone().replace(tzinfo=None)
        oid = ObjectId(str(data["oid"]))
        return ts, oid
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid cursor") from exc


def decode_cursor_str(cursor: str) -> tuple[str, ObjectId]:
    """Decode a cursor token to (str, ObjectId).

    Used by lexi_messages, which stores timestamps as ISO strings so the Mongo
    $lt comparison must use a string value, not a datetime object.
    """
    try:
        padding = "=" * (-len(cursor) % 4)
        raw = base64.urlsafe_b64decode(f"{cursor}{padding}".encode("utf-8"))
        data = json.loads(raw.decode("utf-8"))
        ts = str(data["ts"])
        oid = ObjectId(str(data["oid"]))
        return ts, oid
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid cursor") from exc


def build_pagination(
    *,
    total_count: int,
    returned: int,
    has_more: bool,
    next_cursor: str | None,
    prev_cursor: str | None,
    window_start_ts: str | None,
    window_end_ts: str | None,
) -> dict[str, Any]:
    return {
        "total_count": total_count,
        "returned": returned,
        "has_more": has_more,
        "next_cursor": next_cursor,
        "prev_cursor": prev_cursor,
        "window_start_ts": window_start_ts,
        "window_end_ts": window_end_ts,
    }
