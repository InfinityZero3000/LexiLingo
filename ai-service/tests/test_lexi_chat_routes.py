"""Tests for lexi_chat routes not covered by test_lexi_session_management.py.

Covers: create_session, lexi_chat (POST /chat), messages/paged,
messages/metadata, lexi_health, and pipeline helper extraction.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from bson import ObjectId

from api.routes import lexi_chat as lexi_route
from api.services import lexi_chat_service as svc
from api.core.auth import AuthenticatedUser


# ─── Shared fixtures ──────────────────────────────────────────────────────────

def _user(user_id: str = "u1") -> AuthenticatedUser:
    u = MagicMock(spec=AuthenticatedUser)
    u.user_id = user_id
    u.roles = []
    return u


def _quota():
    q = MagicMock()
    q.rpm_used = 1
    q.rpm_limit = 60
    q.rpd_used = 1
    q.rpd_limit = 1000
    q.tpm_used = 100
    q.tpm_limit = 100_000
    q.tpd_used = 100
    q.tpd_limit = 1_000_000
    return q


@pytest.fixture()
def mock_store(monkeypatch):
    store = MagicMock()
    store.has_session = AsyncMock(return_value=False)
    store.get_messages = AsyncMock(return_value=[])
    store.set_session = AsyncMock()
    store.init_messages = AsyncMock()
    store.append_message = AsyncMock()
    store.get_session = AsyncMock(return_value=None)
    store.delete_session = AsyncMock()
    store.delete_messages = AsyncMock()
    monkeypatch.setattr(svc, "lexi_store", store)
    return store


@pytest.fixture()
def mock_idempotency(monkeypatch):
    idem = MagicMock()
    idem.get = AsyncMock(return_value=None)
    idem.set = AsyncMock()
    monkeypatch.setattr(svc, "lexi_idempotency_store", idem)
    return idem


def _make_db(session_doc=None, msg_docs=None, count=0):
    db = MagicMock()

    lexi_sessions = MagicMock()
    lexi_sessions.find_one = AsyncMock(return_value=session_doc)
    lexi_sessions.update_one = AsyncMock()
    lexi_sessions.delete_one = AsyncMock()

    lexi_messages = MagicMock()
    lexi_messages.insert_many = AsyncMock()
    lexi_messages.delete_many = AsyncMock()
    lexi_messages.count_documents = AsyncMock(return_value=count)

    docs = msg_docs or []
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=docs)
    lexi_messages.find.return_value = cursor

    def _get(name):
        if name == "lexi_sessions":
            return lexi_sessions
        if name == "lexi_messages":
            return lexi_messages
        return MagicMock()

    db.__getitem__.side_effect = _get
    return db


# ─── create_lexi_session ─────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_create_lexi_session_returns_session_id(mock_store, monkeypatch):
    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: uid)
    db = _make_db()
    user = _user()

    result = await lexi_route.create_lexi_session(
        request=lexi_route.LexiSessionRequest(user_id="u1"),
        db=db,
        current_user=user,
    )

    assert result.success is True
    assert len(result.session_id) == 36  # UUID
    assert result.persona == "lexi"
    mock_store.set_session.assert_awaited_once()
    mock_store.init_messages.assert_awaited_once()


@pytest.mark.asyncio
async def test_create_lexi_session_writes_to_mongo(mock_store, monkeypatch):
    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: uid)
    db = _make_db()

    await lexi_route.create_lexi_session(
        request=lexi_route.LexiSessionRequest(user_id="u1"),
        db=db,
        current_user=_user(),
    )

    db["lexi_sessions"].update_one.assert_awaited_once()
    call_kwargs = db["lexi_sessions"].update_one.call_args
    assert call_kwargs[1]["upsert"] is True


# ─── lexi_chat (POST /chat) ──────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_lexi_chat_returns_response(mock_store, mock_idempotency, monkeypatch):
    """Happy path: pipeline succeeds, response contains lexi_response."""
    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: uid)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    monkeypatch.setattr(lexi_route, "emit_ai_audit_event", AsyncMock())

    pipeline_result = svc.PipelineResult(
        lexi_response="Squawk! Great question!",
        user_text="Hello Lexi",
        message_id="msg-1",
        session_id="sess-1",
        model_used="trace-cag",
        metadata={"pipeline_steps": [], "latency_ms": 100, "quota": {}},
    )
    monkeypatch.setattr(svc, "run_lexi_pipeline", AsyncMock(return_value=pipeline_result))

    db = _make_db()
    request_ctx = MagicMock()
    request_ctx.headers = {"X-Request-Id": "req-1"}

    result = await lexi_route.lexi_chat(
        request_context=request_ctx,
        request=lexi_route.LexiChatRequest(user_id="u1", message="Hello Lexi"),
        x_idempotency_key=None,
        db=db,
        current_user=_user(),
    )

    assert result.success is True
    assert result.lexi_response == "Squawk! Great question!"
    assert result.session_id == "sess-1"


@pytest.mark.asyncio
async def test_lexi_chat_returns_cached_idempotency_response(mock_store, mock_idempotency, monkeypatch):
    """When idempotency key matches, cached response is returned without running pipeline."""
    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: uid)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))

    cached = lexi_route.LexiChatResponse(
        session_id="s1", message_id="m1", lexi_response="Cached!"
    ).model_dump()
    mock_idempotency.get.return_value = cached

    run_pipeline = AsyncMock()
    monkeypatch.setattr(svc, "run_lexi_pipeline", run_pipeline)

    db = _make_db()
    request_ctx = MagicMock()
    request_ctx.headers = {}

    result = await lexi_route.lexi_chat(
        request_context=request_ctx,
        request=lexi_route.LexiChatRequest(user_id="u1", message="Hello"),
        x_idempotency_key="key-123",
        db=db,
        current_user=_user(),
    )

    assert result.lexi_response == "Cached!"
    run_pipeline.assert_not_called()


@pytest.mark.asyncio
async def test_lexi_chat_uses_hot_cached_session_without_mongo_lookup(
    mock_store,
    mock_idempotency,
    monkeypatch,
):
    """Hot cache path should avoid Mongo session ownership lookup before pipeline."""
    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    monkeypatch.setattr(lexi_route, "emit_ai_audit_event", AsyncMock())

    cached_history = [{"role": "user", "content": "previous turn"}]
    mock_store.get_session.return_value = {"session_id": "s1", "user_id": "u1"}
    mock_store.get_messages.return_value = cached_history

    pipeline_result = svc.PipelineResult(
        lexi_response="Fast cached path",
        user_text="Hello again",
        message_id="msg-1",
        session_id="s1",
        model_used="trace-cag",
        metadata={"pipeline_steps": [], "latency_ms": 50, "quota": {}},
    )
    run_pipeline = AsyncMock(return_value=pipeline_result)
    monkeypatch.setattr(svc, "run_lexi_pipeline", run_pipeline)

    db = _make_db(session_doc={"session_id": "s1", "user_id": "u1"})
    request_ctx = MagicMock()
    request_ctx.headers = {}

    result = await lexi_route.lexi_chat(
        request_context=request_ctx,
        request=lexi_route.LexiChatRequest(
            user_id="u1",
            session_id="s1",
            message="Hello again",
        ),
        x_idempotency_key=None,
        db=db,
        current_user=_user("u1"),
    )

    assert result.lexi_response == "Fast cached path"
    db["lexi_sessions"].find_one.assert_not_awaited()
    assert run_pipeline.await_args.kwargs["history"] == cached_history


@pytest.mark.asyncio
async def test_lexi_chat_quota_exceeded_raises_429(mock_store, monkeypatch):
    """Quota enforcement raises HTTPException 429 before pipeline runs."""
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: uid)
    monkeypatch.setattr(
        lexi_route,
        "enforce_user_quota",
        AsyncMock(side_effect=HTTPException(status_code=429, detail="quota exceeded")),
    )
    run_pipeline = AsyncMock()
    monkeypatch.setattr(svc, "run_lexi_pipeline", run_pipeline)

    db = _make_db()
    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(user_id="u1", message="Hello"),
            x_idempotency_key=None,
            db=db,
            current_user=_user(),
        )

    assert exc_info.value.status_code == 429
    run_pipeline.assert_not_called()


@pytest.mark.asyncio
async def test_lexi_chat_rejects_session_owned_by_another_user(
    mock_store,
    mock_idempotency,
    monkeypatch,
):
    """A supplied session_id must belong to the authenticated user before idempotency/pipeline."""
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))

    mock_store.has_session = AsyncMock(return_value=False)
    mock_store.get_messages = AsyncMock(return_value=[])
    db = _make_db(session_doc={"session_id": "sess-other", "user_id": "owner-1"})

    run_pipeline = AsyncMock()
    monkeypatch.setattr(svc, "run_lexi_pipeline", run_pipeline)

    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="attacker-1",
                session_id="sess-other",
                message="continue",
            ),
            x_idempotency_key="key-123",
            db=db,
            current_user=_user("attacker-1"),
        )

    assert exc_info.value.status_code == 403
    run_pipeline.assert_not_called()
    mock_idempotency.get.assert_not_called()


@pytest.mark.asyncio
async def test_lexi_chat_rejects_unknown_supplied_session_id(
    mock_store,
    mock_idempotency,
    monkeypatch,
):
    """Unknown client-supplied session_id is not silently created."""
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))

    mock_store.has_session = AsyncMock(return_value=False)
    mock_store.get_session = AsyncMock(return_value=None)
    mock_store.get_messages = AsyncMock(return_value=[])
    db = _make_db(session_doc=None)

    run_pipeline = AsyncMock()
    monkeypatch.setattr(svc, "run_lexi_pipeline", run_pipeline)

    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="u1",
                session_id="missing-session",
                message="hello",
            ),
            x_idempotency_key="key-123",
            db=db,
            current_user=_user("u1"),
        )

    assert exc_info.value.status_code == 404
    run_pipeline.assert_not_called()
    mock_idempotency.get.assert_not_called()


@pytest.mark.asyncio
async def test_lexi_stream_rejects_session_owned_by_another_user(
    mock_store,
    monkeypatch,
):
    """Streaming endpoint should fail ownership preflight before returning SSE 200."""
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))

    db = _make_db(session_doc={"session_id": "sess-other", "user_id": "owner-1"})
    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_stream_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="attacker-1",
                session_id="sess-other",
                message="hello",
            ),
            db=db,
            current_user=_user("attacker-1"),
        )

    assert exc_info.value.status_code == 403


@pytest.mark.asyncio
async def test_lexi_stream_rejects_unknown_supplied_session_id(
    mock_store,
    monkeypatch,
):
    """Unknown client-supplied session_id should fail before the stream opens."""
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    mock_store.get_session = AsyncMock(return_value=None)

    db = _make_db(session_doc=None)
    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_stream_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="u1",
                session_id="missing-session",
                message="hello",
            ),
            db=db,
            current_user=_user("u1"),
        )

    assert exc_info.value.status_code == 404


# ─── get_lexi_messages_paged ─────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_lexi_messages_paged_returns_empty_page(monkeypatch):
    """No messages → pagination with empty list and zero count."""
    session_doc = {"session_id": "s1", "user_id": "u1"}
    db = _make_db(session_doc=session_doc, msg_docs=[], count=0)
    monkeypatch.setattr(svc, "ensure_session_owner", AsyncMock(return_value=session_doc))

    result = await lexi_route.get_lexi_messages_paged(
        session_id="s1",
        limit=20,
        cursor=None,
        db=db,
        current_user=_user(),
    )

    assert result["success"] is True
    assert result["messages"] == []
    assert result["pagination"]["total_count"] == 0
    assert result["pagination"]["has_more"] is False


@pytest.mark.asyncio
async def test_get_lexi_messages_paged_returns_messages(monkeypatch):
    """2 messages returned, pagination reflects count."""
    from bson import ObjectId as OID
    doc1 = {"id": "m1", "session_id": "s1", "role": "user", "content": "Hi", "timestamp": "2024-01-01T00:00:00", "_id": OID()}
    doc2 = {"id": "m2", "session_id": "s1", "role": "assistant", "content": "Hello!", "timestamp": "2024-01-01T00:00:01", "_id": OID()}
    session_doc = {"session_id": "s1", "user_id": "u1"}
    db = _make_db(session_doc=session_doc, msg_docs=[doc2, doc1], count=2)
    monkeypatch.setattr(svc, "ensure_session_owner", AsyncMock(return_value=session_doc))

    result = await lexi_route.get_lexi_messages_paged(
        session_id="s1",
        limit=20,
        cursor=None,
        db=db,
        current_user=_user(),
    )

    assert result["success"] is True
    assert len(result["messages"]) == 2
    assert result["pagination"]["total_count"] == 2


@pytest.mark.asyncio
async def test_get_lexi_messages_paged_invalid_limit_raises_400(monkeypatch):
    from fastapi import HTTPException

    session_doc = {"session_id": "s1", "user_id": "u1"}
    db = _make_db(session_doc=session_doc)
    monkeypatch.setattr(svc, "ensure_session_owner", AsyncMock(return_value=session_doc))

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.get_lexi_messages_paged(
            session_id="s1",
            limit=0,
            cursor=None,
            db=db,
            current_user=_user(),
        )

    assert exc_info.value.status_code == 400


# ─── get_lexi_messages_metadata ──────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_lexi_messages_metadata_empty_session(monkeypatch):
    """No messages → all nulls in metadata."""
    session_doc = {"session_id": "s1", "user_id": "u1"}
    db = _make_db(session_doc=session_doc, count=0)
    monkeypatch.setattr(svc, "ensure_session_owner", AsyncMock(return_value=session_doc))

    result = await lexi_route.get_lexi_messages_metadata(
        session_id="s1",
        db=db,
        current_user=_user(),
    )

    assert result["success"] is True
    assert result["metadata"]["total_count"] == 0
    assert result["metadata"]["has_messages"] is False
    assert result["metadata"]["latest_cursor"] is None


@pytest.mark.asyncio
async def test_get_lexi_messages_metadata_with_messages(monkeypatch):
    """2 messages → cursors and timestamps populated."""
    from bson import ObjectId as OID
    latest = {"timestamp": "2024-01-02T00:00:00", "_id": OID()}
    oldest = {"timestamp": "2024-01-01T00:00:00", "_id": OID()}

    session_doc = {"session_id": "s1", "user_id": "u1"}
    db = _make_db(session_doc=session_doc, count=2)
    monkeypatch.setattr(svc, "ensure_session_owner", AsyncMock(return_value=session_doc))

    # Override find to return latest/oldest in the right order per call
    call_count = [0]
    async def _to_list(length):
        call_count[0] += 1
        return [latest] if call_count[0] == 1 else [oldest]

    cursor_mock = MagicMock()
    cursor_mock.sort.return_value = cursor_mock
    cursor_mock.limit.return_value = cursor_mock
    cursor_mock.to_list = _to_list
    db["lexi_messages"].find.return_value = cursor_mock

    result = await lexi_route.get_lexi_messages_metadata(
        session_id="s1",
        db=db,
        current_user=_user(),
    )

    assert result["metadata"]["total_count"] == 2
    assert result["metadata"]["has_messages"] is True
    assert result["metadata"]["latest_cursor"] is not None
    assert result["metadata"]["oldest_cursor"] is not None


# ─── lexi_health ─────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_lexi_health_returns_ok():
    result = await lexi_route.lexi_health()
    assert result["status"] == "ok"
    assert result["service"] == "lexi-chat"
    assert "text-chat" in result["capabilities"]
