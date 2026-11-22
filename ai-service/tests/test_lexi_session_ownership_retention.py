"""Session ownership, retention and cross-path idempotency for Lexi chat.

The stores run their real in-memory fallback (Redis disabled), not mocks.
"""

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from api.core.auth import AuthenticatedUser, assert_session_owner
from api.routes import lexi_chat as lexi_route
from api.services import lexi_chat_service as svc
from api.services.lexi_idempotency_store import LexiIdempotencyStore
from api.services.lexi_session_store import LEXI_MESSAGE_CACHE_LIMIT, LexiSessionStore

U1 = AuthenticatedUser(user_id="u1", claims={})


@pytest.fixture
def idem_store(monkeypatch):
    store = LexiIdempotencyStore()
    monkeypatch.setattr(store, "_redis", AsyncMock(return_value=None))
    monkeypatch.setattr(svc, "lexi_idempotency_store", store)
    return store


@pytest.mark.parametrize("session", [{"session_id": "s"}, {"session_id": "s", "user_id": ""}, {"user_id": "u2"}, None])
def test_session_without_matching_owner_is_refused(session):
    with pytest.raises(HTTPException) as exc:
        assert_session_owner(session, U1)
    assert exc.value.status_code == 403


def test_owner_passes():
    assert_session_owner({"user_id": "u1"}, U1)


@pytest.mark.asyncio
async def test_ownerless_lexi_session_is_not_open_to_any_user():
    db = MagicMock()
    db.__getitem__.return_value.find_one = AsyncMock(return_value={"session_id": "s"})
    with pytest.raises(HTTPException) as exc:
        await svc.ensure_session_owner("s", U1, db)
    assert exc.value.status_code == 403


def test_a_turn_never_rewrites_the_session_owner():
    update = svc.session_turn_update("intruder", "2026-11-19T00:00:00+00:00", 2)
    assert "user_id" not in update["$set"]
    assert update["$setOnInsert"]["user_id"] == "intruder"
    assert update["$set"]["last_activity_at"].tzinfo is not None  # a BSON Date, so TTL can fire


def test_mongo_message_carries_a_date_for_ttl_but_the_cache_copy_stays_json():
    message = {"id": "m", "role": "user", "content": "hi", "timestamp": "2026-11-19T00:00:00+00:00"}
    doc = svc.mongo_message_doc(message, "s", "u1")
    assert doc["stored_at"].tzinfo is not None
    assert "stored_at" not in message


@pytest.mark.asyncio
async def test_list_sessions_queries_the_scoped_user_not_the_path_placeholder():
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.to_list = AsyncMock(return_value=[])
    db = MagicMock()
    db.__getitem__.return_value.find.return_value = cursor
    await lexi_route.list_lexi_sessions(user_id="demo_user", db=db, current_user=U1)
    db.__getitem__.return_value.find.assert_called_once_with({"user_id": "u1"})


@pytest.mark.asyncio
async def test_cached_message_list_is_capped(monkeypatch):
    store = LexiSessionStore()
    monkeypatch.setattr(store, "_redis", AsyncMock(return_value=None))
    for i in range(LEXI_MESSAGE_CACHE_LIMIT + 7):
        await store.append_message("s", {"id": str(i)})
    assert len(await store.get_messages("s")) == LEXI_MESSAGE_CACHE_LIMIT

    await store.append_messages("t", [{"id": str(i)} for i in range(LEXI_MESSAGE_CACHE_LIMIT + 2)])
    messages = await store.get_messages("t")
    assert len(messages) == LEXI_MESSAGE_CACHE_LIMIT
    assert messages[-1]["id"] == str(LEXI_MESSAGE_CACHE_LIMIT + 1)


@pytest.mark.asyncio
async def test_same_key_while_running_is_refused_then_replayed(idem_store):
    args = dict(user_id="u1", session_id="s", idempotency_key="k", request_hash="h")
    assert await svc.replay_or_claim(**args) is None
    with pytest.raises(HTTPException) as exc:
        await svc.replay_or_claim(**args)  # /chat fallback while /stream still runs
    assert exc.value.status_code == 409

    await svc.remember_response(**args, response={"lexi_response": "ok"}, model_used="groq/x")
    await idem_store.release(user_id="u1", session_id="s", idempotency_key="k")
    assert await svc.replay_or_claim(**args) == {"lexi_response": "ok"}


@pytest.mark.asyncio
async def test_canned_apology_is_not_replayed(idem_store):
    args = dict(user_id="u1", session_id="s", idempotency_key="k", request_hash="h")
    await svc.replay_or_claim(**args)
    await svc.remember_response(
        **args, response={"lexi_response": svc.SAFE_FIXED_RESPONSE}, model_used=svc.SAFE_RESPONSE_MODEL
    )
    await idem_store.release(user_id="u1", session_id="s", idempotency_key="k")
    assert await svc.replay_or_claim(**args) is None  # retry runs again instead


@pytest.mark.asyncio
async def test_stream_releases_its_claim_even_when_the_pipeline_fails(idem_store, monkeypatch):
    async def _boom(*_args, **_kwargs):
        raise RuntimeError("pipeline down")
        yield  # pragma: no cover

    monkeypatch.setattr(svc, "_stream_lexi_chat", _boom)
    await idem_store.claim(user_id="u1", session_id="s", idempotency_key="k")
    request = svc.LexiChatRequest(user_id="u1", session_id="s", message="hi")
    with pytest.raises(RuntimeError):
        async for _ in svc.stream_lexi_chat(
            request=request, session_id="s", prechecked_history=[], quota=None, start_time=0.0,
            request_id="r", current_user=U1, db=MagicMock(), idempotency_key="k", request_hash="h",
        ):
            pass
    assert await idem_store.claim(user_id="u1", session_id="s", idempotency_key="k")


@pytest.mark.asyncio
async def test_replayed_stream_ends_with_the_stored_done_event():
    events = [e async for e in svc.replay_lexi_stream({"lexi_response": "Hello", "message_id": "m1"})]
    assert events[0].startswith("event: chunk")
    assert events[-1].startswith("event: done") and '"message_id": "m1"' in events[-1]
