"""Contracts from the 2026-11 ai-service audit: each test is a defect that shipped."""

import asyncio
import json
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, create_autospec

import httpx
import numpy as np
import pytest

from api.core import groq_key_pool as pool
from api.core.quota_guard import UserQuotaGuard
from api.core.redis_client import RedisClient
from api.services import learner_observation_spool as spool
from api.services import retrieval_service_v3 as rs
from api.services.trace_cag import generate as gen
from api.services.trace_cag import llm_client, nodes_v2

# conftest replaces reconnect for every test; these need the real one.
_REAL_RECONNECT = RedisClient.__dict__["reconnect"].__func__


@pytest.fixture(autouse=True)
def _clean_state(monkeypatch):
    pool._PARKED_UNTIL.clear()
    llm_client._PROVIDER_TOKEN_WINDOW.clear()
    llm_client._PROVIDER_NEXT_REQUEST_AT.clear()
    from api.services.trace_cag import provider_state

    provider_state._PROVIDER_DISABLED_UNTIL.clear()
    monkeypatch.setattr(RedisClient, "_down_until", 0.0)
    yield
    pool._PARKED_UNTIL.clear()
    provider_state._PROVIDER_DISABLED_UNTIL.clear()


# ── Groq ──────────────────────────────────────────────────────────────────


class _Pool:
    """Two keys; hands out the first that is not parked, like the real one."""

    def __init__(self):
        self.keys = ["key-a", "key-b"]

    async def acquire(self, estimated_tokens=0):
        return next((k for k in self.keys if not pool.groq_key_is_parked(k)), None)


def _sse(*objects):
    return "".join(f"data: {json.dumps(o)}\n\n" for o in objects) + "data: [DONE]\n\n"


def _use_transport(monkeypatch, handler):
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    monkeypatch.setattr(gen, "_get_httpx_client", lambda _p: client)
    monkeypatch.setattr(llm_client, "_get_httpx_client", lambda _p: client)
    p = _Pool()
    monkeypatch.setattr(pool, "try_acquire_groq_key", create_autospec(pool.try_acquire_groq_key, side_effect=p.acquire))
    monkeypatch.setattr(pool, "get_available_groq_key", create_autospec(pool.get_available_groq_key, side_effect=p.acquire))
    monkeypatch.setattr(pool, "get_configured_key_count", lambda: 2)
    monkeypatch.setattr(pool, "get_groq_key_pool", lambda: p)
    monkeypatch.setattr(pool, "release_groq_key", create_autospec(pool.release_groq_key))
    used = []

    async def _record(key, tokens):
        used.append(str(key))

    monkeypatch.setattr(pool, "record_groq_key_usage", _record)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setenv("TRACECAG_GROQ_RPM", "60000")
    return used


async def _stream():
    return [
        t async for t in gen.stream_llm_tokens(
            system_prompt="s", messages=[{"role": "user", "content": "hi"}], user_input="hi"
        )
    ]


@pytest.mark.asyncio
@pytest.mark.parametrize("refusal", ["status_429", "mid_stream_frame", "status_503"])
async def test_stream_moves_to_another_key_instead_of_reporting_an_outage(monkeypatch, refusal):
    seen = []

    def handler(request):
        key = request.headers["authorization"].removeprefix("Bearer ")
        seen.append(key)
        if len(seen) == 1:
            if refusal == "status_429":
                return httpx.Response(429, text="Rate limit reached: tokens per day (TPD)")
            if refusal == "status_503":
                return httpx.Response(503, text="over capacity")
            return httpx.Response(200, text=_sse({"error": {"message": "tokens per day exceeded"}}))
        return httpx.Response(200, text=_sse({"choices": [{"delta": {"content": "Hello"}}]}))

    _use_transport(monkeypatch, handler)
    assert await _stream() == ["Hello"]
    if refusal != "status_503":
        assert seen == ["key-a", "key-b"] and pool.groq_key_is_parked("key-a")


@pytest.mark.asyncio
async def test_stream_never_restarts_a_reply_the_learner_already_sees(monkeypatch):
    calls = []

    def handler(_request):
        calls.append(1)
        return httpx.Response(200, text=_sse({"choices": [{"delta": {"content": "Hel"}}]}, {"error": "boom"}))

    _use_transport(monkeypatch, handler)
    assert await _stream() == ["Hel"]
    assert len(calls) == 1


@pytest.mark.asyncio
async def test_json_call_rotates_on_429_and_bills_the_key_that_answered(monkeypatch):
    def handler(request):
        if request.headers["authorization"].endswith("key-a"):
            return httpx.Response(429, headers={"Retry-After": "20"}, text="tokens per minute")
        return httpx.Response(
            200, json={"choices": [{"message": {"content": "ok"}}], "usage": {"total_tokens": 9}}
        )

    used = _use_transport(monkeypatch, handler)
    started = asyncio.get_running_loop().time()
    assert await llm_client.groq_chat([{"role": "user", "content": "x"}], max_tokens=10) == "ok"
    assert asyncio.get_running_loop().time() - started < 2
    assert used == ["key-b"]


def test_a_403_cannot_sideline_the_pool_for_long():
    assert llm_client.groq_refusal_seconds(403, None, "") <= 60
    assert llm_client.groq_refusal_seconds(429, "246", "tokens per minute") <= 30
    assert llm_client.groq_refusal_seconds(429, None, "tokens per day") >= 300
    assert llm_client.groq_refusal_seconds(503, None, "") == 0


def test_token_window_does_not_grow_when_pacing_is_off(monkeypatch):
    monkeypatch.delenv("TRACECAG_GROQ_TPM", raising=False)
    for _ in range(50):
        llm_client._token_window_record("groq:x", "groq", 100)
    assert not llm_client._PROVIDER_TOKEN_WINDOW


# ── Diagnosis is evidence only when something graded it ────────────────────


async def _diagnose(monkeypatch, content, policy="auto"):
    monkeypatch.setattr(nodes_v2, "get_gateway", AsyncMock(return_value=SimpleNamespace(_models={})))
    monkeypatch.setattr(pool, "get_available_groq_key", create_autospec(pool.get_available_groq_key, return_value="k"))
    monkeypatch.setattr(pool, "record_groq_key_usage", create_autospec(pool.record_groq_key_usage))
    response = None if content is None else httpx.Response(
        200, json={"choices": [{"message": {"content": content}}], "usage": {"total_tokens": 5}}
    )
    monkeypatch.setattr(
        nodes_v2, "_throttled_post_json", create_autospec(nodes_v2._throttled_post_json, return_value=response)
    )
    return await nodes_v2.diagnose_node(
        {"user_input": "I likes it", "learner_profile": {"level": "B1"}, "diagnosis_policy": policy}
    )


@pytest.mark.asyncio
@pytest.mark.parametrize("content", [None, "sorry, I cannot", "{}", '{"errors": '])
async def test_a_diagnosis_that_did_not_run_is_not_a_clean_one(monkeypatch, content):
    out = await _diagnose(monkeypatch, content)
    assert out["diagnosis_graded"] is False
    assert out["models_used"] == ["rule_fallback"]
    assert gen.cache_write_allowed({**out, "retrieval_trace": []}) is False


@pytest.mark.asyncio
async def test_a_real_diagnosis_is_graded(monkeypatch):
    out = await _diagnose(monkeypatch, '{"errors": [], "intent": "correct", "confidence": 0.9}')
    assert out["diagnosis_graded"] is True


@pytest.mark.asyncio
async def test_ungraded_turn_is_not_spooled(monkeypatch):
    from api.core.config import settings

    monkeypatch.setattr(settings, "LEARNER_STATE_MODE", "read")
    monkeypatch.setattr(spool, "get_learner_observation_spool", lambda: pytest.fail("must not spool"))
    out = await spool.persist_trace_observations(
        user_id="u", session_id="s", turn_id="t", skill="writing",
        trace_result={"diagnosis_errors": [], "diagnosis_graded": False},
    )
    assert out["observation_count"] == 0


@pytest.mark.asyncio
async def test_native_hint_uses_groq_when_the_local_model_is_not_registered(monkeypatch):
    monkeypatch.setattr(nodes_v2, "get_gateway", AsyncMock(return_value=SimpleNamespace(_models={})))
    monkeypatch.setattr(nodes_v2, "groq_chat", create_autospec(nodes_v2.groq_chat, return_value="Động từ chia theo chủ ngữ."))
    state = {"diagnosis_errors": [{"span": "likes", "type": "verb_form"}],
             "learner_profile": {"level": "A1", "native_language": "Vietnamese"}}
    out = await nodes_v2.vietnamese_node(state)
    assert out == {"native_hint": "Động từ chia theo chủ ngữ.", "models_used": ["groq_native"]}

    nodes_v2.groq_chat.return_value = None
    assert (await nodes_v2.vietnamese_node(state))["models_used"] == ["native_fallback"]


# ── Spool ──────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
@pytest.mark.parametrize("age_days, status", [(1, "retry"), (40, "dead")])
async def test_our_own_bug_does_not_spend_an_observations_attempts(age_days, status):
    forwarder = spool.SpoolForwarder.__new__(spool.SpoolForwarder)
    forwarder._max_backoff_seconds = 60
    forwarder._collection = SimpleNamespace(update_one=AsyncMock())
    created = (datetime.now(UTC) - timedelta(days=age_days)).replace(tzinfo=None)
    await forwarder._reschedule_after_failure(
        {"attempt_count": 10, "created_at": created}, "e1", TypeError("datetime is not JSON serializable")
    )
    update = forwarder._collection.update_one.await_args.args[1]
    assert update["$set"]["status"] == status
    if status == "retry":
        assert update["$inc"] == {"attempt_count": -1}


# ── Redis down ─────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_redis_outage_is_tried_once_for_everyone(monkeypatch):
    monkeypatch.setattr(RedisClient, "_benchmark_redis_disabled", classmethod(lambda cls: False))
    monkeypatch.setattr(RedisClient, "_instance", None)
    attempts = []

    async def _down(cls):
        attempts.append(1)
        await asyncio.sleep(0.01)
        raise RuntimeError("down")

    monkeypatch.setattr(RedisClient, "_reconnect_once", classmethod(_down))
    results = await asyncio.gather(*(_REAL_RECONNECT(RedisClient) for _ in range(20)), return_exceptions=True)
    assert all(isinstance(r, RuntimeError) for r in results)
    assert len(attempts) == 1


@pytest.mark.asyncio
async def test_redis_reconnect_is_shared_and_not_torn_down_by_the_next_waiter(monkeypatch):
    monkeypatch.setattr(RedisClient, "_benchmark_redis_disabled", classmethod(lambda cls: False))
    monkeypatch.setattr(RedisClient, "_instance", None)
    built = []

    async def _build(cls):
        await asyncio.sleep(0.01)
        built.append(object())
        cls._instance = built[-1]
        return built[-1]

    monkeypatch.setattr(RedisClient, "_reconnect_once", classmethod(_build))
    results = await asyncio.gather(*(_REAL_RECONNECT(RedisClient) for _ in range(10)))
    assert len(built) == 1 and set(map(id, results)) == {id(built[0])}


@pytest.mark.asyncio
async def test_quota_check_survives_redis_failing(monkeypatch):
    import api.core.quota_guard as qg

    monkeypatch.setattr(qg, "get_redis", create_autospec(qg.get_redis, side_effect=RuntimeError("down")))
    closed = await UserQuotaGuard().check_and_consume("u", "e", fail_closed=True)
    assert (closed.allowed, closed.backend_available) == (False, False)
    assert (await UserQuotaGuard().check_and_consume("u", "e")).allowed is True


# ── Retrieval ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize("restricted", [False, True])
def test_matmul_retrieval_ranks_like_the_loop_it_replaced(restricted):
    rng = np.random.default_rng(1)
    matrix = rng.normal(size=(300, 32)).astype(np.float32)
    matrix[:, :6] += 1.0
    matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
    svc = rs.RetrievalServiceV3.__new__(rs.RetrievalServiceV3)
    svc.config = rs.RetrievalConfig()
    svc._concept_cache = {f"c{i}": {"title": f"t{i}"} for i in range(300)}
    svc._concept_embeddings = {f"c{i}": matrix[i] for i in range(300)}
    query = matrix[3]
    subset = [f"c{i}" for i in range(0, 300, 3)] + ["missing"] if restricted else None
    pool_ids = subset or list(svc._concept_cache)
    expected = sorted(
        ((c, float(query @ svc._concept_embeddings[c])) for c in pool_ids if c in svc._concept_cache),
        key=lambda x: x[1], reverse=True,
    )
    expected = [(c, s) for c, s in expected if s >= svc.config.min_similarity][:10]
    got = svc._similar_concepts(query, subset, 10)
    assert [c for c, _ in got] == [c for c, _ in expected]
    assert [s for _, s in got] == pytest.approx([s for _, s in expected], abs=1e-5)


# ── Public surface ─────────────────────────────────────────────────────────


def test_the_legacy_v3_routes_are_gone():
    from api.main import app

    paths = {getattr(r, "path", "") for r in app.routes}
    assert not any("graph-analytics" in p for p in paths)
    assert "/api/v1/ai/analyze" not in paths


@pytest.mark.asyncio
@pytest.mark.parametrize("env, shown", [("production", False), ("development", True)])
async def test_a_500_does_not_describe_our_insides_in_production(monkeypatch, env, shown):
    from fastapi import HTTPException

    import api.main as main

    monkeypatch.setattr(main.settings, "ENVIRONMENT", env)
    request = SimpleNamespace(method="GET", url=SimpleNamespace(path="/x"))
    response = await main._hide_internal_error_details(request, HTTPException(500, "mongodb://internal:27017 refused"))
    assert (b"mongodb" in response.body) is shown
    kept = await main._hide_internal_error_details(request, HTTPException(503, "AI quota backend unavailable"))
    assert b"quota" in kept.body
