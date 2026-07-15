from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from api.routes import chat as chat_route
from api.routes import lexi_chat as lexi_route
from api.routes import topic_chat as topic_route
from api.services import lexi_chat_service as lexi_svc
from api.core.auth import AuthenticatedUser


@pytest.fixture
def mock_chat_db():
    db = MagicMock()

    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value={"session_id": "chat_s1", "user_id": "u1"})

    chat_messages = MagicMock()
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=[])
    chat_messages.find.return_value = cursor

    def get_collection(name):
        if name == "chat_sessions":
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection
    return db


@pytest.fixture
def mock_topic_db():
    db = MagicMock()

    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value={"session_id": "topic_s1"})

    chat_messages = MagicMock()
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=[])
    chat_messages.find.return_value = cursor

    def get_collection(name):
        if name == "chat_sessions":
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection
    return db


@pytest.fixture
def mock_lexi_db():
    db = MagicMock()

    lexi_sessions = MagicMock()
    lexi_sessions.find_one = AsyncMock(return_value=None)

    lexi_messages = MagicMock()
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.to_list = AsyncMock(return_value=[])
    lexi_messages.find.return_value = cursor

    def get_collection(name):
        if name == "lexi_sessions":
            return lexi_sessions
        if name == "lexi_messages":
            return lexi_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection
    return db


@pytest.fixture
def mock_lexi_store(monkeypatch):
    store = MagicMock()
    store.get_session = AsyncMock(return_value=None)
    store.get_messages = AsyncMock(return_value=[])
    store.set_session = AsyncMock()
    store.delete_messages = AsyncMock()
    store.append_message = AsyncMock()
    monkeypatch.setattr(lexi_svc, "lexi_store", store)
    return store


@pytest.mark.asyncio
async def test_chat_messages_limit_positive_uses_limit_cursor(mock_chat_db):
    cursor = mock_chat_db["chat_messages"].find.return_value
    cursor.to_list = AsyncMock(
        return_value=[
            {
                "role": "user",
                "content": "hello",
                "timestamp": datetime.now(UTC),
            }
        ]
    )

    result = await chat_route.get_session_messages(
        session_id="chat_s1",
        limit=1,
        db=mock_chat_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
    )

    assert len(result) == 1
    cursor.limit.assert_called_once_with(1)
    cursor.to_list.assert_awaited_once_with(length=1)


@pytest.mark.asyncio
async def test_topic_messages_limit_zero_loads_full_history_batches(mock_topic_db):
    cursor = mock_topic_db["chat_messages"].find.return_value
    cursor.to_list = AsyncMock(
        side_effect=[
            [
                {
                    "message_id": "m1",
                    "session_id": "topic_s1",
                    "content": "hello",
                    "role": "user",
                    "timestamp": datetime(2026, 4, 16, 10, 0, 0),
                },
                {
                    "message_id": "m2",
                    "session_id": "topic_s1",
                    "content": "hi",
                    "role": "assistant",
                    "timestamp": datetime(2026, 4, 16, 10, 0, 1),
                },
            ],
            [],
        ]
    )

    result = await topic_route.get_topic_messages(
        session_id="topic_s1",
        limit=0,
        db=mock_topic_db,
    )

    assert "messages" in result
    assert len(result["messages"]) == 2
    cursor.limit.assert_not_called()
    assert cursor.to_list.await_count == 1


@pytest.mark.asyncio
async def test_topic_messages_limit_positive_uses_limit_cursor(mock_topic_db):
    cursor = mock_topic_db["chat_messages"].find.return_value
    cursor.to_list = AsyncMock(
        return_value=[
            {
                "message_id": "m1",
                "session_id": "topic_s1",
                "content": "hello",
                "role": "user",
                "timestamp": datetime(2026, 4, 16, 10, 0, 0),
            }
        ]
    )

    result = await topic_route.get_topic_messages(
        session_id="topic_s1",
        limit=1,
        db=mock_topic_db,
    )

    assert len(result["messages"]) == 1
    cursor.limit.assert_called_once_with(1)
    cursor.to_list.assert_awaited_once_with(length=1)


@pytest.mark.asyncio
async def test_lexi_messages_returns_cached_when_cache_is_complete(
    mock_lexi_db, mock_lexi_store
):
    mock_lexi_db["lexi_sessions"].find_one.return_value = {
        "session_id": "lexi_s1",
        "message_count": 2,
    }
    mock_lexi_store.get_session.return_value = {
        "session_id": "lexi_s1",
        "user_id": "u1",
    }
    mock_lexi_store.get_messages.return_value = [
        {
            "id": "m1",
            "role": "user",
            "content": "hello",
            "timestamp": "2026-04-16T10:00:00",
        },
        {
            "id": "m2",
            "role": "assistant",
            "content": "hi",
            "timestamp": "2026-04-16T10:00:01",
        },
    ]

    result = await lexi_route.get_lexi_messages(
        session_id="lexi_s1",
        db=mock_lexi_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
        full=True,
    )

    assert result["success"] is True
    assert len(result["messages"]) == 2
    mock_lexi_db["lexi_messages"].find.assert_not_called()


@pytest.mark.asyncio
async def test_lexi_messages_uses_cached_payload_when_session_doc_missing(
    mock_lexi_db, mock_lexi_store
):
    mock_lexi_db["lexi_sessions"].find_one.return_value = None
    mock_lexi_store.get_session.return_value = {
        "session_id": "lexi_s1",
        "user_id": "u1",
    }
    mock_lexi_store.get_messages.return_value = [
        {
            "id": "m1",
            "role": "user",
            "content": "cached",
            "timestamp": "2026-04-16T10:00:00",
        }
    ]

    result = await lexi_route.get_lexi_messages(
        session_id="lexi_s1",
        db=mock_lexi_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
        full=True,
    )

    assert result["success"] is True
    assert len(result["messages"]) == 1
    assert result["messages"][0]["content"] == "cached"


@pytest.mark.asyncio
async def test_lexi_messages_raises_404_when_no_db_and_no_cache(
    mock_lexi_db, mock_lexi_store
):
    mock_lexi_db["lexi_sessions"].find_one.return_value = None
    mock_lexi_store.get_session.return_value = None

    with pytest.raises(HTTPException) as exc:
        await lexi_route.get_lexi_messages(
            session_id="missing",
            db=mock_lexi_db,
            current_user=AuthenticatedUser(user_id="u1", claims={}),
            full=True,
        )

    assert exc.value.status_code == 404
