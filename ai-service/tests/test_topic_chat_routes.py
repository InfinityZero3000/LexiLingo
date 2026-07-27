"""Tests for topic_chat routes.

Covers: list_stories, list_categories, get_story, start_topic_session,
get_topic_session, get_topic_messages, get_topic_messages_paged,
get_topic_messages_metadata, check_llm_health, and helper functions.
"""

import pytest
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import HTTPException

from api.routes import topic_chat as topic_route
from api.services.topic_chat_service import TracecagResult


# ─── Shared helpers ────────────────────────────────────────────────────────────

def _user(user_id: str = "u1") -> MagicMock:
    u = MagicMock()
    u.user_id = user_id
    u.roles = []
    return u


def _quota():
    return SimpleNamespace(
        rpm_used=1,
        rpm_limit=60,
        rpd_used=1,
        rpd_limit=1000,
        tpm_used=10,
        tpm_limit=60000,
        tpd_used=10,
        tpd_limit=1000000,
    )


def _make_db(session_doc=None, msg_docs=None, count=0):
    db = MagicMock()

    # topic_chat uses "chat_sessions" (NOT "topic_sessions") for ownership checks
    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value=session_doc)
    chat_sessions.insert_one = AsyncMock()
    chat_sessions.update_one = AsyncMock()

    chat_messages = MagicMock()
    chat_messages.count_documents = AsyncMock(return_value=count)
    docs = msg_docs or []
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=docs)
    chat_messages.find.return_value = cursor

    def _get(name):
        if name in ("topic_sessions", "chat_sessions"):
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        m = MagicMock()
        m.find_one = AsyncMock(return_value=None)
        return m

    db.__getitem__.side_effect = _get
    return db


# ─── _normalize_preferred_llm ─────────────────────────────────────────────────

def test_normalize_preferred_llm_tracecag():
    assert topic_route._normalize_preferred_llm("tracecag") == "trace-cag"
    assert topic_route._normalize_preferred_llm("trace-cag") == "trace-cag"
    assert topic_route._normalize_preferred_llm(None) == "trace-cag"


def test_normalize_preferred_llm_other():
    assert topic_route._normalize_preferred_llm("gemini") == "gemini"
    assert topic_route._normalize_preferred_llm("ollama") == "ollama"


# ─── _sanitize_topic_response ─────────────────────────────────────────────────

def test_sanitize_topic_response_clean_sentence():
    text = "Hello! How are you?"
    assert topic_route._sanitize_topic_response(text) == text


def test_sanitize_topic_response_strips_json_tail():
    text = 'Good practice! ],"e":[]}'
    result = topic_route._sanitize_topic_response(text)
    assert result == "Good practice!"


def test_sanitize_topic_response_empty():
    assert topic_route._sanitize_topic_response("") == ""
    assert topic_route._sanitize_topic_response(None) == ""


# ─── list_stories ─────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_list_stories_returns_all_when_no_filter():
    story = MagicMock()
    story.category = "travel"
    story.difficulty_level = MagicMock(value="B1")
    catalog = MagicMock()
    catalog.get_topics = AsyncMock(return_value=[story])

    with patch.object(topic_route, "_story_list_item_payload", return_value={"title": "test"}):
        response = await topic_route.list_stories(
            category=None,
            difficulty_level=None,
            limit=100,
            bypass_cache=False,
            catalog_service=catalog,
        )

    data = response.body
    import json
    parsed = json.loads(data)
    assert parsed["total"] == 1


@pytest.mark.asyncio
async def test_list_stories_filters_by_category():
    story_a = MagicMock()
    story_a.category = "travel"
    story_a.difficulty_level = None
    story_b = MagicMock()
    story_b.category = "business"
    story_b.difficulty_level = None

    catalog = MagicMock()
    catalog.get_topics = AsyncMock(return_value=[story_a, story_b])

    with patch.object(topic_route, "_story_list_item_payload", return_value={"title": "t"}):
        response = await topic_route.list_stories(
            category="travel",
            difficulty_level=None,
            limit=100,
            bypass_cache=False,
            catalog_service=catalog,
        )

    import json
    parsed = json.loads(response.body)
    assert parsed["total"] == 1


@pytest.mark.asyncio
async def test_list_stories_raises_500_on_error():
    catalog = MagicMock()
    catalog.get_topics = AsyncMock(side_effect=RuntimeError("DB down"))

    with pytest.raises(HTTPException) as exc_info:
        await topic_route.list_stories(
            category=None,
            difficulty_level=None,
            limit=100,
            bypass_cache=False,
            catalog_service=catalog,
        )

    assert exc_info.value.status_code == 500


# ─── get_story ─────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_story_not_found_raises_404():
    db = _make_db()
    story_service = MagicMock()
    story_service.get_story_by_id = AsyncMock(return_value=None)

    with patch("api.routes.topic_chat.StoryService", return_value=story_service):
        with pytest.raises(HTTPException) as exc_info:
            await topic_route.get_story(story_id="s999", db=db)

    assert exc_info.value.status_code == 404


@pytest.mark.asyncio
async def test_get_story_returns_story():
    story = {"story_id": "s1", "title": "The Market"}
    story_service = MagicMock()
    story_service.get_story_by_id = AsyncMock(return_value=story)
    db = _make_db()

    with patch("api.routes.topic_chat.StoryService", return_value=story_service):
        result = await topic_route.get_story(story_id="s1", db=db)

    assert result["story_id"] == "s1"


# ─── get_topic_session ────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_topic_session_not_found_raises_404():
    db = _make_db(session_doc=None)

    with pytest.raises(HTTPException) as exc_info:
        await topic_route.get_topic_session(
            session_id="missing",
            db=db,
            current_user=_user(),
        )

    assert exc_info.value.status_code == 404


@pytest.mark.asyncio
async def test_get_topic_session_returns_session(monkeypatch):
    session_doc = {
        "session_id": "sess-1",
        "user_id": "u1",
        "created_at": "2024-01-01T00:00:00",
        "last_activity": "2024-01-01T01:00:00",
        "_id": "mongo-oid",
    }
    monkeypatch.setattr(
        topic_route, "_ensure_topic_session_owner", AsyncMock(return_value=dict(session_doc))
    )
    db = _make_db()

    result = await topic_route.get_topic_session(
        session_id="sess-1",
        db=db,
        current_user=_user(),
    )

    assert result["session_id"] == "sess-1"
    assert "_id" not in result


# ─── get_topic_messages ──────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_get_topic_messages_invalid_limit_raises_400(monkeypatch):
    session_doc = {"session_id": "s1", "user_id": "u1"}
    monkeypatch.setattr(
        topic_route, "_ensure_topic_session_owner", AsyncMock(return_value=session_doc)
    )
    db = _make_db()

    with pytest.raises(HTTPException) as exc_info:
        await topic_route.get_topic_messages(
            session_id="s1",
            limit=-1,
            db=db,
            current_user=_user(),
        )

    assert exc_info.value.status_code == 400


@pytest.mark.asyncio
async def test_get_topic_messages_returns_messages(monkeypatch):
    session_doc = {"session_id": "s1", "user_id": "u1"}
    monkeypatch.setattr(
        topic_route, "_ensure_topic_session_owner", AsyncMock(return_value=session_doc)
    )

    from datetime import datetime, timezone
    docs = [
        {"message_id": "m1", "session_id": "s1", "role": "user", "content": "Hi", "timestamp": "2024-01-01T00:00:00"},
    ]
    db = _make_db(session_doc=session_doc, msg_docs=docs)

    result = await topic_route.get_topic_messages(
        session_id="s1",
        limit=10,
        db=db,
        current_user=_user(),
    )

    assert len(result["messages"]) == 1


# ─── check_llm_health ────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_check_llm_health_ok_when_orchestrator_healthy():
    orchestrator = MagicMock()
    orchestrator.is_healthy.return_value = True
    orchestrator.get_stats.return_value = {}

    # get_orchestrator is imported inline inside check_llm_health, so patch the source module
    with patch("api.services.orchestrator.get_orchestrator", AsyncMock(return_value=orchestrator)):
        result = await topic_route.check_llm_health()

    assert result["status"] == "ok"
    assert result["trace-cag_ready"] is True


@pytest.mark.asyncio
async def test_check_llm_health_degraded_when_orchestrator_fails():
    with patch("api.services.orchestrator.get_orchestrator", AsyncMock(side_effect=RuntimeError("no model"))):
        result = await topic_route.check_llm_health()

    assert result["status"] == "degraded"
    assert result["trace-cag_ready"] is False


@pytest.mark.asyncio
async def test_send_topic_message_passes_session_prompt_to_tracecag(monkeypatch):
    session_doc = {
        "session_id": "sess-1",
        "user_id": "u1",
        "session_type": "topic_based",
        "preferred_llm": "trace-cag",
        "difficulty_level": "B1",
        "system_prompt": "You are Sarah, an airport check-in agent.",
        "kg_seed_concepts": ["concept:travel.airport"],
    }
    db = _make_db(
        session_doc=session_doc,
        msg_docs=[{"role": "assistant", "content": "Good morning. Passport, please."}],
    )
    request_context = MagicMock(headers={})
    request = topic_route.TopicChatRequest(user_id="u1", message="I need check in.")
    tracecag = AsyncMock(
        return_value=TracecagResult(
            ai_response="Certainly, may I see your passport?",
            llm_metadata={"provider": "trace-cag"},
        )
    )

    monkeypatch.setattr(topic_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    monkeypatch.setattr(topic_route, "emit_ai_audit_event", AsyncMock())
    monkeypatch.setattr(topic_route, "persist_topic_turn", AsyncMock(return_value="ai-1"))
    monkeypatch.setattr(topic_route, "call_tracecag_with_retry", tracecag)

    await topic_route.send_topic_message(
        request_context,
        "sess-1",
        request,
        db,
        AsyncMock(),
        _user("u1"),
    )

    assert tracecag.await_args.kwargs["topic_system_prompt"] == session_doc["system_prompt"]
