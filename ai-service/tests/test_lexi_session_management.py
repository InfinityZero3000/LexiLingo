import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock
from fastapi import HTTPException
from starlette.requests import Request

from api.routes import lexi_chat as lexi_route
from api.services import lexi_chat_service as svc
from api.core.auth import AuthenticatedUser


@pytest.fixture
def mock_store(monkeypatch):
    store = MagicMock()
    store.has_session = AsyncMock(return_value=False)
    store.get_messages = AsyncMock(return_value=[])
    store.set_session = AsyncMock()
    store.delete_messages = AsyncMock()
    store.append_message = AsyncMock()
    store.get_session = AsyncMock(return_value=None)
    store.delete_session = AsyncMock()
    store.init_messages = AsyncMock()
    monkeypatch.setattr(svc, "lexi_store", store)
    return store


@pytest.fixture
def mock_db():
    db = MagicMock()

    lexi_sessions = MagicMock()
    lexi_sessions.find_one = AsyncMock(return_value=None)
    lexi_sessions.update_one = AsyncMock()
    lexi_sessions.delete_one = AsyncMock()

    lexi_messages = MagicMock()
    lexi_messages.insert_many = AsyncMock()
    lexi_messages.delete_many = AsyncMock()

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


@pytest.mark.asyncio
async def test_list_lexi_sessions_returns_mongo_rows(mock_db):
    rows = [
        {
            "session_id": "s1",
            "user_id": "u1",
            "title": "Session 1",
            "created_at": "2026-04-14T00:00:00",
            "updated_at": "2026-04-14T00:05:00",
            "message_count": 4,
        },
        {
            "session_id": "s2",
            "user_id": "u1",
            "title": "Session 2",
            "created_at": "2026-04-14T01:00:00",
            "updated_at": "2026-04-14T01:10:00",
            "message_count": 7,
        },
    ]

    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.to_list = AsyncMock(return_value=rows)
    mock_db["lexi_sessions"].find.return_value = cursor

    result = await lexi_route.list_lexi_sessions(
        user_id="u1",
        db=mock_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
    )

    assert result.success is True
    assert len(result.sessions) == 2
    assert result.sessions[0].session_id == "s1"
    assert result.sessions[1].message_count == 7


@pytest.mark.asyncio
async def test_rename_lexi_session_updates_db_and_cache(mock_db, mock_store):
    mock_db["lexi_sessions"].update_one.return_value = MagicMock(matched_count=1)
    mock_db["lexi_sessions"].find_one.return_value = {
        "session_id": "s1",
        "user_id": "u1",
        "title": "Old",
    }
    mock_store.get_session.return_value = {
        "session_id": "s1",
        "title": "Old",
        "updated_at": "2026-04-14T00:00:00",
    }

    req = lexi_route.LexiSessionRenameRequest(title="  New Title  ")
    result = await lexi_route.rename_lexi_session(
        session_id="s1",
        request=req,
        db=mock_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
    )

    assert result["success"] is True
    assert result["title"] == "New Title"
    mock_db["lexi_sessions"].update_one.assert_awaited_once()
    mock_store.set_session.assert_awaited_once()


@pytest.mark.asyncio
async def test_rename_lexi_session_not_found_raises_404(mock_db, mock_store):
    mock_db["lexi_sessions"].update_one.return_value = MagicMock(matched_count=0)

    req = lexi_route.LexiSessionRenameRequest(title="X")
    with pytest.raises(HTTPException) as exc:
        await lexi_route.rename_lexi_session(
            session_id="missing",
            request=req,
            db=mock_db,
            current_user=AuthenticatedUser(user_id="u1", claims={}),
        )

    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_get_messages_fallback_rehydrates_cache(mock_db, mock_store):
    mock_store.has_session.return_value = False

    mock_db["lexi_sessions"].find_one.return_value = {
        "session_id": "s1",
        "user_id": "u1",
        "created_at": "2026-04-14T00:00:00",
        "updated_at": "2026-04-14T00:10:00",
        "title": "Lexi Chat",
        "message_count": 2,
        "persona": "lexi",
    }

    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.to_list = AsyncMock(
        return_value=[
            {
                "id": "m1",
                "role": "user",
                "content": "hello",
                "timestamp": "2026-04-14T00:01:00",
            },
            {
                "id": "m2",
                "role": "assistant",
                "content": "hi",
                "timestamp": "2026-04-14T00:01:01",
            },
        ]
    )
    mock_db["lexi_messages"].find.return_value = cursor

    result = await lexi_route.get_lexi_messages(
        session_id="s1",
        db=mock_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
        full=True,
    )

    assert result["success"] is True
    assert result["session_id"] == "s1"
    assert len(result["messages"]) == 2
    mock_store.set_session.assert_awaited_once()
    assert mock_store.append_message.await_count == 2


@pytest.mark.asyncio
async def test_delete_lexi_session_cleans_db_and_cache(mock_db, mock_store):
    mock_db["lexi_sessions"].find_one.return_value = {
        "session_id": "s1",
        "user_id": "u1",
    }
    result = await lexi_route.delete_lexi_session(
        session_id="s1",
        db=mock_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
    )

    assert result["success"] is True
    mock_db["lexi_sessions"].delete_one.assert_awaited_once_with({"session_id": "s1"})
    mock_db["lexi_messages"].delete_many.assert_awaited_once_with({"session_id": "s1"})
    mock_store.delete_session.assert_awaited_once_with("s1")
    mock_store.delete_messages.assert_awaited_once_with("s1")


def test_sanitize_lexi_response_preserves_valid_bold_markdown():
    text = "Ah, a **wonderful** question!"
    sanitized = svc._sanitize_lexi_response(text)

    assert sanitized == text


def test_sanitize_lexi_response_fixes_misaligned_bold_markers():
    raw = (
        "1. Daily practice** (15 mins), **\n"
        "2. Focus on one skill at a time\n"
        "3. Keep **good** habits"
    )

    sanitized = svc._sanitize_lexi_response(raw)

    assert "Daily practice**" not in sanitized
    assert "(15 mins), **" not in sanitized
    assert "**good**" in sanitized
    assert sanitized.count("**") == 2


@pytest.mark.asyncio
async def test_lexi_stream_starts_before_session_store_finishes(
    mock_db,
    mock_store,
    monkeypatch,
):
    session_gate = asyncio.Event()

    async def _slow_set_session(*_args, **_kwargs):
        await session_gate.wait()

    mock_store.set_session.side_effect = _slow_set_session
    monkeypatch.setattr(
        lexi_route,
        "enforce_user_quota",
        AsyncMock(
            return_value=MagicMock(
                rpm_used=1,
                rpm_limit=30,
                rpd_used=1,
                rpd_limit=500,
            )
        ),
    )

    request_context = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/lexi/stream",
            "headers": [],
        }
    )
    response = await lexi_route.lexi_stream_chat(
        request_context=request_context,
        request=lexi_route.LexiChatRequest(
            user_id="u1",
            message="hello",
            enable_tts=False,
        ),
        db=mock_db,
        current_user=AuthenticatedUser(user_id="u1", claims={}),
    )

    first_chunk = await asyncio.wait_for(
        anext(response.body_iterator),
        timeout=0.1,
    )

    assert first_chunk == "event: thinking\ndata: {}\n\n"
    mock_store.set_session.assert_not_awaited()
    session_gate.set()
    await response.body_iterator.aclose()


@pytest.mark.asyncio
async def test_lexi_stream_returns_503_when_quota_check_times_out(
    mock_db,
    mock_store,
    monkeypatch,
):
    async def _stalled_quota(*_args, **_kwargs):
        await asyncio.Event().wait()

    monkeypatch.setenv("LEXI_STREAM_QUOTA_TIMEOUT_SECONDS", "0.01")
    monkeypatch.setattr(lexi_route, "enforce_user_quota", _stalled_quota)

    request_context = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/lexi/stream",
            "headers": [],
        }
    )

    with pytest.raises(HTTPException) as exc:
        await lexi_route.lexi_stream_chat(
            request_context=request_context,
            request=lexi_route.LexiChatRequest(
                user_id="u1",
                session_id="s1",
                message="hello",
                enable_tts=False,
            ),
            db=mock_db,
            current_user=AuthenticatedUser(user_id="u1", claims={}),
        )

    assert exc.value.status_code == 503
    mock_store.has_session.assert_not_awaited()


def test_sanitize_lexi_response_fixes_escaped_misaligned_bold_markers():
    raw = (
        "1. Daily practice\\*\\* (15 mins), \\*\\*\n"
        "2. Focus on one skill at a time\\*\\*\n"
        "3. Keep \\*\\*good\\*\\* habits"
    )

    sanitized = svc._sanitize_lexi_response(raw)

    assert "Daily practice**" not in sanitized
    assert "(15 mins), **" not in sanitized
    assert "**good**" in sanitized
    assert sanitized.count("**") == 2
