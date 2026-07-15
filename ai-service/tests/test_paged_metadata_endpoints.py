from datetime import datetime
from unittest.mock import AsyncMock, MagicMock

import pytest
from bson import ObjectId

from api.core.auth import AuthenticatedUser
from api.routes import chat as chat_route
from api.routes import lexi_chat as lexi_route
from api.routes import topic_chat as topic_route


def _mock_cursor(rows):
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=rows)
    return cursor


@pytest.mark.asyncio
async def test_chat_messages_paged_returns_cursor_pagination_payload():
    docs_desc = [
        {
            "_id": ObjectId(),
            "message_id": "m3",
            "session_id": "chat_s1",
            "content": "third",
            "role": "assistant",
            "timestamp": datetime(2026, 4, 16, 10, 0, 2),
        },
        {
            "_id": ObjectId(),
            "message_id": "m2",
            "session_id": "chat_s1",
            "content": "second",
            "role": "user",
            "timestamp": datetime(2026, 4, 16, 10, 0, 1),
        },
        {
            "_id": ObjectId(),
            "message_id": "m1",
            "session_id": "chat_s1",
            "content": "first",
            "role": "assistant",
            "timestamp": datetime(2026, 4, 16, 10, 0, 0),
        },
    ]

    chat_messages = MagicMock()
    chat_messages.find.return_value = _mock_cursor(docs_desc)
    chat_messages.count_documents = AsyncMock(return_value=3)
    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value={"session_id": "chat_s1", "user_id": "u1"})

    db = MagicMock()

    def get_collection(name):
        if name == "chat_sessions":
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection

    result = await chat_route.get_session_messages_paged(
        session_id="chat_s1",
        limit=2,
        cursor=None,
        db=db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
    )

    assert result["success"] is True
    assert len(result["messages"]) == 2
    assert result["messages"][0]["id"] == "m2"
    assert result["messages"][1]["id"] == "m3"
    assert result["pagination"]["total_count"] == 3
    assert result["pagination"]["has_more"] is True
    assert result["pagination"]["next_cursor"] is not None


@pytest.mark.asyncio
async def test_chat_messages_metadata_returns_expected_fields():
    latest_doc = {
        "_id": ObjectId(),
        "message_id": "m9",
        "session_id": "chat_s1",
        "content": "latest",
        "role": "assistant",
        "timestamp": datetime(2026, 4, 16, 10, 0, 9),
    }
    oldest_doc = {
        "_id": ObjectId(),
        "message_id": "m1",
        "session_id": "chat_s1",
        "content": "oldest",
        "role": "user",
        "timestamp": datetime(2026, 4, 16, 10, 0, 1),
    }

    chat_messages = MagicMock()
    chat_messages.count_documents = AsyncMock(return_value=9)
    chat_messages.find.side_effect = [
        _mock_cursor([latest_doc]),
        _mock_cursor([oldest_doc]),
    ]
    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value={"session_id": "chat_s1", "user_id": "u1"})

    db = MagicMock()

    def get_collection(name):
        if name == "chat_sessions":
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection

    result = await chat_route.get_session_messages_metadata(
        session_id="chat_s1",
        db=db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
    )

    metadata = result["metadata"]
    assert metadata["total_count"] == 9
    assert metadata["has_messages"] is True
    assert metadata["latest_cursor"] is not None
    assert metadata["oldest_cursor"] is not None
    assert metadata["latest_ts"] is not None
    assert metadata["oldest_ts"] is not None


@pytest.mark.asyncio
async def test_topic_messages_paged_returns_cursor_pagination_payload():
    docs_desc = [
        {
            "_id": ObjectId(),
            "message_id": "m3",
            "session_id": "topic_s1",
            "content": "third",
            "role": "assistant",
            "timestamp": datetime(2026, 4, 16, 10, 0, 2),
        },
        {
            "_id": ObjectId(),
            "message_id": "m2",
            "session_id": "topic_s1",
            "content": "second",
            "role": "user",
            "timestamp": datetime(2026, 4, 16, 10, 0, 1),
        },
        {
            "_id": ObjectId(),
            "message_id": "m1",
            "session_id": "topic_s1",
            "content": "first",
            "role": "assistant",
            "timestamp": datetime(2026, 4, 16, 10, 0, 0),
        },
    ]

    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value={"session_id": "topic_s1"})

    chat_messages = MagicMock()
    chat_messages.find.return_value = _mock_cursor(docs_desc)
    chat_messages.count_documents = AsyncMock(return_value=3)

    db = MagicMock()

    def get_collection(name):
        if name == "chat_sessions":
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection

    result = await topic_route.get_topic_messages_paged(
        session_id="topic_s1",
        limit=2,
        cursor=None,
        db=db,
    )

    assert len(result["messages"]) == 2
    assert result["messages"][0]["id"] == "m2"
    assert result["messages"][1]["id"] == "m3"
    assert result["pagination"]["total_count"] == 3
    assert result["pagination"]["has_more"] is True
    assert result["pagination"]["next_cursor"] is not None


@pytest.mark.asyncio
async def test_topic_messages_metadata_returns_expected_fields():
    latest_doc = {
        "_id": ObjectId(),
        "message_id": "m9",
        "session_id": "topic_s1",
        "content": "latest",
        "role": "assistant",
        "timestamp": datetime(2026, 4, 16, 10, 0, 9),
    }
    oldest_doc = {
        "_id": ObjectId(),
        "message_id": "m1",
        "session_id": "topic_s1",
        "content": "oldest",
        "role": "user",
        "timestamp": datetime(2026, 4, 16, 10, 0, 1),
    }

    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value={"session_id": "topic_s1"})

    chat_messages = MagicMock()
    chat_messages.count_documents = AsyncMock(return_value=9)
    chat_messages.find.side_effect = [
        _mock_cursor([latest_doc]),
        _mock_cursor([oldest_doc]),
    ]

    db = MagicMock()

    def get_collection(name):
        if name == "chat_sessions":
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection

    result = await topic_route.get_topic_messages_metadata(
        session_id="topic_s1",
        db=db,
    )

    metadata = result["metadata"]
    assert metadata["total_count"] == 9
    assert metadata["has_messages"] is True
    assert metadata["latest_cursor"] is not None
    assert metadata["oldest_cursor"] is not None


@pytest.mark.asyncio
async def test_lexi_messages_paged_returns_cursor_pagination_payload():
    docs_desc = [
        {
            "_id": ObjectId(),
            "id": "m3",
            "session_id": "lexi_s1",
            "content": "third",
            "role": "assistant",
            "timestamp": "2026-04-16T10:00:02",
        },
        {
            "_id": ObjectId(),
            "id": "m2",
            "session_id": "lexi_s1",
            "content": "second",
            "role": "user",
            "timestamp": "2026-04-16T10:00:01",
        },
        {
            "_id": ObjectId(),
            "id": "m1",
            "session_id": "lexi_s1",
            "content": "first",
            "role": "assistant",
            "timestamp": "2026-04-16T10:00:00",
        },
    ]

    lexi_sessions = MagicMock()
    lexi_sessions.find_one = AsyncMock(return_value={"session_id": "lexi_s1"})

    lexi_messages = MagicMock()
    lexi_messages.find.return_value = _mock_cursor(docs_desc)
    lexi_messages.count_documents = AsyncMock(return_value=3)

    db = MagicMock()

    def get_collection(name):
        if name == "lexi_sessions":
            return lexi_sessions
        if name == "lexi_messages":
            return lexi_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection

    result = await lexi_route.get_lexi_messages_paged(
        session_id="lexi_s1",
        limit=2,
        cursor=None,
        db=db,
    )

    assert result["success"] is True
    assert len(result["messages"]) == 2
    assert result["messages"][0]["id"] == "m2"
    assert result["messages"][1]["id"] == "m3"
    assert result["pagination"]["total_count"] == 3
    assert result["pagination"]["has_more"] is True
    assert result["pagination"]["next_cursor"] is not None


@pytest.mark.asyncio
async def test_lexi_messages_metadata_returns_expected_fields():
    latest_doc = {
        "_id": ObjectId(),
        "id": "m9",
        "session_id": "lexi_s1",
        "content": "latest",
        "role": "assistant",
        "timestamp": "2026-04-16T10:00:09",
    }
    oldest_doc = {
        "_id": ObjectId(),
        "id": "m1",
        "session_id": "lexi_s1",
        "content": "oldest",
        "role": "user",
        "timestamp": "2026-04-16T10:00:01",
    }

    lexi_sessions = MagicMock()
    lexi_sessions.find_one = AsyncMock(return_value={"session_id": "lexi_s1"})

    lexi_messages = MagicMock()
    lexi_messages.count_documents = AsyncMock(return_value=9)
    lexi_messages.find.side_effect = [
        _mock_cursor([latest_doc]),
        _mock_cursor([oldest_doc]),
    ]

    db = MagicMock()

    def get_collection(name):
        if name == "lexi_sessions":
            return lexi_sessions
        if name == "lexi_messages":
            return lexi_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection

    result = await lexi_route.get_lexi_messages_metadata(
        session_id="lexi_s1",
        db=db,
    )

    metadata = result["metadata"]
    assert metadata["total_count"] == 9
    assert metadata["has_messages"] is True
    assert metadata["latest_cursor"] is not None
    assert metadata["oldest_cursor"] is not None
