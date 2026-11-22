"""Regression tests for the chat-session / response-shaping debt audit.

Stores and helpers are patched with ``autospec=True`` so a stale kwarg or a
renamed method fails here instead of passing against a permissive mock.
"""

import inspect
import json
from unittest.mock import AsyncMock, MagicMock, create_autospec, patch

import pytest
from fastapi import HTTPException
from motor.motor_asyncio import AsyncIOMotorCollection
from starlette.requests import Request

from api.core.auth import AuthenticatedUser
from api.core.quota_guard import QuotaDecision
from api.routes import chat as chat_route
from api.routes import lexi_chat as lexi_route
from api.routes import topic_chat as topic_route
from api.services import lexi_chat_service as svc
from api.services.lexi_idempotency_store import LexiIdempotencyStore
from api.services.lexi_session_store import LexiSessionStore

USER = AuthenticatedUser(user_id="u1", claims={})


@pytest.fixture
def store(monkeypatch):
    s = create_autospec(LexiSessionStore, instance=True)
    s.get_session.return_value = None
    s.get_messages.return_value = []
    monkeypatch.setattr(svc, "lexi_store", s)
    return s


@pytest.fixture
def idem(monkeypatch):
    i = create_autospec(LexiIdempotencyStore, instance=True)
    i.get.return_value = None
    monkeypatch.setattr(svc, "lexi_idempotency_store", i)
    return i


def _quota() -> QuotaDecision:
    return QuotaDecision(
        allowed=True, rpm_used=1, rpd_used=1, rpm_limit=30, rpd_limit=500,
        tpm_used=0, tpd_used=0, tpm_limit=1000, tpd_limit=10000, backend_available=True,
    )


def _db(session_doc=None, msg_docs=None):
    # Mongo is mocked (no mongomock in the venv); the collections are
    # spec'd on the real Motor class so a misspelt method raises.
    sessions = MagicMock(spec=AsyncIOMotorCollection)
    sessions.find_one = AsyncMock(return_value=session_doc)
    sessions.update_one = AsyncMock()
    messages = MagicMock(spec=AsyncIOMotorCollection)
    messages.insert_many = AsyncMock()
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=msg_docs or [])
    messages.find.return_value = cursor
    db = MagicMock()
    db.__getitem__.side_effect = lambda n: sessions if n == "lexi_sessions" else messages
    db.sessions, db.messages = sessions, messages
    return db


# ─── Redis cache vs Mongo ───────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_expired_cache_is_rehydrated_so_next_turn_keeps_its_context(store):
    doc = {
        "session_id": "s1", "user_id": "u1", "message_count": 12,
        "title": "Trip", "story_context": "At the airport",
    }
    msgs = [
        {"id": "m1", "role": "user", "content": "hi", "timestamp": "2026-01-01T00:00:00+00:00"},
        {"id": "m2", "role": "assistant", "content": "hello", "timestamp": "2026-01-01T00:00:01+00:00"},
    ]
    history = await svc.prepare_existing_lexi_session("s1", USER, _db(doc, list(reversed(msgs))))

    assert [m["id"] for m in history] == ["m1", "m2"]
    cached = store.set_session.await_args.args[1]
    assert cached["message_count"] == 12
    assert cached["story_context"] == "At the airport"
    assert store.append_message.await_count == 2


@pytest.mark.asyncio
async def test_evicted_message_list_falls_back_to_mongo_instead_of_empty_history(store):
    store.get_session.return_value = {
        "session_id": "s1", "user_id": "u1", "message_count": 4, "story_context": "kept",
    }
    store.get_messages.return_value = []
    msgs = [{"id": "m1", "role": "user", "content": "hi", "timestamp": "2026-01-01T00:00:00+00:00"}]
    db = _db({"session_id": "s1", "user_id": "u1", "message_count": 4}, msgs)

    history = await svc.prepare_existing_lexi_session("s1", USER, db)

    assert [m["id"] for m in history] == ["m1"]
    # Mongo has no story_context for this legacy row; the cached one must survive.
    assert store.set_session.await_args.args[1]["story_context"] == "kept"


@pytest.mark.asyncio
async def test_hot_cache_still_skips_mongo(store):
    store.get_session.return_value = {"session_id": "s1", "user_id": "u1", "message_count": 2}
    store.get_messages.return_value = [{"role": "user", "content": "x"}]
    db = _db()

    assert await svc.prepare_existing_lexi_session("s1", USER, db) == [{"role": "user", "content": "x"}]
    db.sessions.find_one.assert_not_awaited()
    store.set_session.assert_not_awaited()


@pytest.mark.asyncio
async def test_session_creation_persists_story_context_to_mongo(store):
    db = _db()
    await svc.create_lexi_session_for_user("s1", "u1", "At the airport", db)
    assert db.sessions.update_one.await_args.args[1]["$set"]["story_context"] == "At the airport"


@pytest.mark.asyncio
async def test_create_route_goes_through_the_shared_helper(store):
    db = _db()
    with patch.object(lexi_route, "enforce_user_scope", autospec=True, side_effect=lambda cu, uid: uid), \
            patch.object(svc, "create_lexi_session_for_user", autospec=True) as helper:
        result = await lexi_route.create_lexi_session(
            request=lexi_route.LexiSessionRequest(user_id="u1"), db=db, current_user=USER
        )
    helper.assert_awaited_once()
    assert helper.await_args.kwargs["session_id"] == result.session_id


# ─── /lexi/chat idempotent replay must not be billed ────────────────────────


def _chat_kwargs(session_id):
    return dict(
        request_context=Request({"type": "http", "headers": []}),
        request=lexi_route.LexiChatRequest(user_id="u1", session_id=session_id, message="hello"),
        x_idempotency_key="k1",
        db=_db({"session_id": "s1", "user_id": "u1"}),
        current_user=USER,
    )


@pytest.mark.asyncio
async def test_idempotent_replay_does_not_charge_the_quota(store, idem):
    idem.get.return_value = lexi_route.LexiChatResponse(
        session_id="s1", message_id="m1", lexi_response="Cached!"
    ).model_dump()
    with patch.object(lexi_route, "enforce_user_scope", autospec=True, side_effect=lambda cu, uid: uid), \
            patch.object(lexi_route, "_enforce_chat_quota", autospec=True) as quota, \
            patch.object(svc, "run_lexi_pipeline", autospec=True) as pipeline:
        result = await lexi_route.lexi_chat(**_chat_kwargs("s1"))

    assert result.lexi_response == "Cached!"
    quota.assert_not_awaited()
    pipeline.assert_not_awaited()


@pytest.mark.asyncio
async def test_new_turn_still_charges_the_quota_once(store, idem):
    store.get_session.return_value = {"session_id": "s1", "user_id": "u1"}
    result = svc.PipelineResult(
        lexi_response="hi", user_text="hello", message_id="m1", session_id="s1",
        metadata={"pipeline_steps": [], "latency_ms": 1, "quota": {}},
    )
    with patch.object(lexi_route, "enforce_user_scope", autospec=True, side_effect=lambda cu, uid: uid), \
            patch.object(lexi_route, "_enforce_chat_quota", autospec=True) as quota, \
            patch.object(lexi_route, "emit_ai_audit_event", autospec=True) as audit, \
            patch.object(svc, "run_lexi_pipeline", autospec=True, return_value=result):
        await lexi_route.lexi_chat(**_chat_kwargs("s1"))

    quota.assert_awaited_once()
    assert audit.await_args.args[0]["status"] == "success"


@pytest.mark.asyncio
async def test_over_quota_new_chat_does_not_create_a_session(store, idem):
    kwargs = _chat_kwargs(None)
    with patch.object(lexi_route, "enforce_user_scope", autospec=True, side_effect=lambda cu, uid: uid), \
            patch.object(lexi_route, "_enforce_chat_quota", autospec=True,
                         side_effect=HTTPException(status_code=429, detail="quota")), \
            patch.object(svc, "create_lexi_session_for_user", autospec=True) as create:
        with pytest.raises(HTTPException) as exc:
            await lexi_route.lexi_chat(**kwargs)

    assert exc.value.status_code == 429
    create.assert_not_awaited()


def test_audit_status_flags_the_canned_apology():
    assert svc.audit_status(svc.SAFE_RESPONSE_MODEL) == "degraded"
    assert svc.audit_status("groq/qwen") == "success"


# ─── /lexi/stream ────────────────────────────────────────────────────────────


async def _run_stream(monkeypatch, store, *, tokens, db, request_story=None, provider=None):
    import api.core.audit_emitter as audit_mod
    import api.services.learner_observation_spool as spool_mod
    import api.services.orchestrator as orch_mod
    import api.services.trace_cag.benchmark.ranking as ranking_mod
    import api.services.trace_cag.cache_utils as cache_mod
    import api.services.trace_cag.nodes_v2 as nodes_mod
    from api.services.trace_cag.graph import TraceCAGPipeline

    pipeline = create_autospec(TraceCAGPipeline, instance=True)
    pipeline.analyze_for_streaming.return_value = {
        "diagnosis_errors": [], "grammar_score": 0.8, "fluency_score": 0.8,
        "vocabulary_level": "B1", "cache_hit": False, "cache_policy": "on",
        "retrieval_trace": [],
    }
    orchestrator = create_autospec(orch_mod.AIOrchestrator, instance=True)
    orchestrator.pipeline = pipeline

    async def _tokens(*, system_prompt, messages, user_input, max_tokens=512,
                      allow_gemini_fallback=True, provider_info=None):
        provider_info.update(provider or {"provider": "groq", "model": "m"})
        for t in tokens:
            yield t

    write_cache = create_autospec(cache_mod._write_cache_entry)
    audit = create_autospec(audit_mod.emit_ai_audit_event)
    for mod, name, fake in [
        (orch_mod, "get_orchestrator", create_autospec(orch_mod.get_orchestrator, return_value=orchestrator)),
        (nodes_mod, "build_generation_prompt",
         create_autospec(nodes_mod.build_generation_prompt, return_value=("sys", []))),
        (nodes_mod, "stream_llm_tokens", create_autospec(nodes_mod.stream_llm_tokens, side_effect=_tokens)),
        (cache_mod, "_write_cache_entry", write_cache),
        (ranking_mod, "_update_ranker_from_generation",
         create_autospec(ranking_mod._update_ranker_from_generation)),
        (audit_mod, "emit_ai_audit_event", audit),
        (spool_mod, "persist_trace_observations",
         create_autospec(spool_mod.persist_trace_observations,
                         return_value={"observation_count": 0, "observation_durability_degraded": False})),
    ]:
        monkeypatch.setattr(mod, name, fake)

    events = [
        e async for e in svc.stream_lexi_chat(
            request=lexi_route.LexiChatRequest(
                user_id="u1", session_id="s1", message="hello", enable_tts=False,
                story_context=request_story,
            ),
            session_id="s1",
            prechecked_history=[],
            quota=_quota(),
            start_time=0.0,
            request_id="r1",
            current_user=USER,
            db=db,
        )
    ]
    done = next(e for e in events if e.startswith("event: done"))
    return json.loads(done.split("data: ", 1)[1]), write_cache, audit


@pytest.mark.asyncio
async def test_stream_turn_without_story_context_keeps_the_sessions_story(monkeypatch, store):
    store.get_session.return_value = {
        "session_id": "s1", "user_id": "u1", "message_count": 2, "story_context": "At the airport",
    }
    done, _, _ = await _run_stream(monkeypatch, store, tokens=["Hello", " there"], db=_db())

    assert store.set_session.await_args.args[1]["story_context"] == "At the airport"
    assert done["story_context"] == "At the airport"
    assert "persistence_degraded" not in done["metadata"]


@pytest.mark.asyncio
async def test_stream_reports_persistence_failure_in_done_metadata(monkeypatch, store):
    db = _db()
    db.messages.insert_many.side_effect = RuntimeError("mongo down")
    done, _, audit = await _run_stream(monkeypatch, store, tokens=["Hello"], db=db)

    assert done["metadata"]["persistence_degraded"] is True
    assert audit.await_args.args[0]["status"] == "success"


@pytest.mark.asyncio
async def test_stream_does_not_cache_a_reply_cut_short_mid_stream(monkeypatch, store):
    done, write_cache, _ = await _run_stream(
        monkeypatch, store, tokens=["Half an"],
        provider={"provider": "groq", "model": "m", "truncated": True}, db=_db(),
    )

    assert done["metadata"]["truncated"] is True
    assert done["lexi_response"] == "Half an"
    write_cache.assert_not_awaited()


@pytest.mark.asyncio
async def test_stream_apology_is_audited_as_degraded(monkeypatch, store):
    done, _, audit = await _run_stream(monkeypatch, store, tokens=[], db=_db())

    assert done["lexi_response"] == svc.SAFE_FIXED_RESPONSE
    assert audit.await_args.args[0]["status"] == "degraded"


# ─── chat.py / topic_chat.py must not leak internals ────────────────────────


@pytest.mark.asyncio
async def test_chat_history_500_does_not_leak_the_exception_text():
    db = MagicMock()
    sessions = MagicMock()
    sessions.find_one = AsyncMock(side_effect=RuntimeError("mongodb://user:pw@host"))
    db.__getitem__.return_value = sessions

    with pytest.raises(HTTPException) as exc:
        await chat_route.get_session_messages(session_id="s", limit=0, db=db, current_user=USER)
    assert exc.value.status_code == 500
    assert "mongodb" not in exc.value.detail


@pytest.mark.asyncio
async def test_user_sessions_500_does_not_leak_and_limit_is_bounded():
    db = MagicMock()
    db.__getitem__.side_effect = RuntimeError("mongodb://user:pw@host")
    with pytest.raises(HTTPException) as exc:
        await chat_route.get_user_sessions(user_id="u1", limit=5, db=db, current_user=USER)
    assert "mongodb" not in exc.value.detail

    bounds = {type(m).__name__: m for m in inspect.signature(chat_route.get_user_sessions)
              .parameters["limit"].default.metadata}
    assert bounds["Ge"].ge == 1 and bounds["Le"].le == 100


@pytest.mark.asyncio
async def test_topic_categories_500_does_not_leak_the_exception_text():
    db = MagicMock()
    with patch.object(topic_route, "StoryService", autospec=True) as story_cls:
        story_cls.return_value.get_categories.side_effect = RuntimeError("mongodb://user:pw@host")
        with pytest.raises(HTTPException) as exc:
            await topic_route.list_categories(db=db)
    assert exc.value.detail == "Failed to list categories"


@pytest.mark.asyncio
async def test_chat_route_audits_the_canned_apology_as_degraded(store, idem):
    store.get_session.return_value = {"session_id": "s1", "user_id": "u1"}
    result = svc.PipelineResult(
        lexi_response=svc.SAFE_FIXED_RESPONSE, user_text="hello", message_id="m1", session_id="s1",
        model_used=svc.SAFE_RESPONSE_MODEL,
        metadata={"pipeline_steps": [], "latency_ms": 1, "quota": {}},
    )
    with patch.object(lexi_route, "enforce_user_scope", autospec=True, side_effect=lambda cu, uid: uid), \
            patch.object(lexi_route, "_enforce_chat_quota", autospec=True), \
            patch.object(lexi_route, "emit_ai_audit_event", autospec=True) as audit, \
            patch.object(svc, "run_lexi_pipeline", autospec=True, return_value=result):
        await lexi_route.lexi_chat(**_chat_kwargs("s1"))

    assert audit.await_args.args[0]["status"] == "degraded"


@pytest.mark.asyncio
async def test_topic_stories_500_does_not_leak_the_exception_text():
    from api.services.topic_catalog_service import TopicCatalogService

    catalog = create_autospec(TopicCatalogService, instance=True)
    catalog.get_topics.side_effect = RuntimeError("mongodb://user:pw@host")
    with pytest.raises(HTTPException) as exc:
        await topic_route.list_stories(catalog_service=catalog)
    assert exc.value.detail == "Failed to list stories"
