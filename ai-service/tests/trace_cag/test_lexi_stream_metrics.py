"""A streamed Lexi turn reports what it really cost: provider tokens, TTFT and why it skipped the cache."""

from __future__ import annotations

import json
from unittest.mock import AsyncMock, MagicMock

import pytest

import api.services.trace_cag.graph as graph_mod
from api.services.trace_cag.llm_client import provider_usage

from .test_stream_failure_modes import _Resp, collect, groq, rig  # noqa: F401  (rig is a fixture)

USAGE = {"prompt_tokens": 812, "completion_tokens": 42, "total_tokens": 854, "prompt_tokens_details": {"cached_tokens": 64}}
# Groq puts usage under x_groq on the finish chunk; with stream_options it also sends an OpenAI-style
# chunk whose choices list is empty. Both shapes are real.
X_GROQ_FINAL = f"data: {json.dumps({'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}], 'x_groq': {'id': 'req_1', 'usage': USAGE}})}"
OPENAI_FINAL = f"data: {json.dumps({'choices': [], 'usage': USAGE})}"
# What qwen/qwen3.8-27b actually sent on 2026-11-24 with include_usage: the finish chunk carries
# usage twice (x_groq and top level), then a choices-less chunk repeats it. Counted once.
GROQ_REAL_TAIL = [
    f"data: {json.dumps({'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}], 'x_groq': {'id': 'req_1', 'usage': USAGE}, 'usage': USAGE})}",
    OPENAI_FINAL,
]


class _CapturingClient:
    def __init__(self, resp):
        self._resp, self.kwargs = resp, {}

    def stream(self, *args, **kwargs):
        from .test_stream_failure_modes import _Ctx

        self.kwargs = kwargs
        return _Ctx(self._resp)


def test_provider_usage_reads_both_groq_shapes_and_nothing_else():
    expected = {"prompt_tokens": 812, "completion_tokens": 42, "cached_tokens": 64}
    assert provider_usage(json.loads(X_GROQ_FINAL[6:])) == expected
    assert provider_usage(json.loads(OPENAI_FINAL[6:])) == expected
    assert provider_usage({"choices": [{"delta": {"content": "hi"}}]}) is None
    assert provider_usage({"usage": None}) is None


@pytest.mark.asyncio
@pytest.mark.parametrize("tail", [[X_GROQ_FINAL], [OPENAI_FINAL], GROQ_REAL_TAIL])
async def test_stream_reports_provider_usage_and_records_the_real_total(rig, tail):  # noqa: F811
    client = _CapturingClient(_Resp(200, [*groq("Hello", " world"), *tail, "data: [DONE]"]))
    rig.clients["groq"] = client

    text, info = await collect()

    assert text == "Hello world"
    assert client.kwargs["json"]["stream_options"] == {"include_usage": True}
    assert info["usage"] == {"prompt_tokens": 812, "completion_tokens": 42, "cached_tokens": 64, "source": "provider"}
    assert rig.record.await_args.args[1] == 854


@pytest.mark.asyncio
async def test_stream_without_a_usage_chunk_says_it_estimated(rig):  # noqa: F811
    rig.clients["groq"] = _CapturingClient(_Resp(200, groq("one", " two")))

    _, info = await collect()

    assert info["usage"]["source"] == "estimated"
    assert info["usage"]["prompt_tokens"] == 0


@pytest.mark.asyncio
async def test_gemini_usage_metadata_is_read(rig):  # noqa: F811
    from .test_stream_failure_modes import _Client

    rig.acquire.return_value = None
    chunk = {
        "candidates": [{"content": {"parts": [{"text": "hi"}]}}],
        "usageMetadata": {"promptTokenCount": 300, "candidatesTokenCount": 9, "cachedContentTokenCount": 0},
    }
    rig.clients["gemini"] = _Client(_Resp(200, [f"data: {json.dumps(chunk)}"]))

    _, info = await collect()

    assert info["usage"] == {"prompt_tokens": 300, "completion_tokens": 9, "cached_tokens": 0, "source": "provider"}


@pytest.mark.asyncio
async def test_streaming_analysis_does_not_write_its_own_turn_metrics(monkeypatch):
    recorded = []
    monkeypatch.setattr(graph_mod, "record_turn_metrics", recorded.append)
    pipeline = object.__new__(graph_mod.TraceCAGPipeline)
    pipeline.compiled = MagicMock()
    pipeline.compiled.ainvoke = AsyncMock(side_effect=lambda state: dict(state))

    await pipeline.analyze_for_streaming(user_input="hi", session_id="s", user_id="u")
    assert recorded == []

    await pipeline.analyze(user_input="hi", session_id="s", user_id="u")
    assert len(recorded) == 1


async def _stream(raw_state, mock_db, monkeypatch, *, provider_info=None, card_facts=""):
    """Drive stream_lexi_chat to its done event; returns (done metadata, recorded turn metrics)."""
    import api.core.audit_emitter as audit_mod
    import api.services.learner_observation_spool as spool_mod
    import api.services.lexi_chat_service as svc
    import api.services.orchestrator as orch_mod
    import api.services.trace_cag.benchmark.ranking as ranking_mod
    import api.services.trace_cag.cache_utils as cache_mod
    import api.services.trace_cag.nodes_v2 as nodes_mod
    import api.services.trace_cag.turn_metrics as metrics_mod
    from api.core.auth import AuthenticatedUser
    from api.routes import lexi_chat as lexi_route

    pipeline = MagicMock()
    pipeline.analyze_for_streaming = AsyncMock(return_value=raw_state)
    monkeypatch.setattr(orch_mod, "get_orchestrator", AsyncMock(return_value=MagicMock(pipeline=pipeline)))
    monkeypatch.setattr(nodes_mod, "build_generation_prompt", lambda _state: ("sys", []))
    monkeypatch.setattr(svc, "_resolve_learner_card", AsyncMock(return_value=svc._CardContext(facts=card_facts)))

    async def _tokens(**kwargs):
        kwargs["provider_info"].update(provider_info or {})
        yield "Fresh"
        yield " answer"

    monkeypatch.setattr(nodes_mod, "stream_llm_tokens", _tokens)
    monkeypatch.setattr(cache_mod, "_write_cache_entry", AsyncMock())
    monkeypatch.setattr(ranking_mod, "_update_ranker_from_generation", MagicMock())
    monkeypatch.setattr(audit_mod, "emit_ai_audit_event", AsyncMock())
    monkeypatch.setattr(
        spool_mod, "persist_trace_observations",
        AsyncMock(return_value={"observation_count": 0, "observation_durability_degraded": False}),
    )
    recorded: list[dict] = []
    monkeypatch.setattr(metrics_mod, "record_turn_metrics", recorded.append)

    events = [
        event
        async for event in svc.stream_lexi_chat(
            request=lexi_route.LexiChatRequest(user_id="u1", session_id="s1", message="um", enable_tts=False),
            session_id="s1",
            prechecked_history=[],
            quota=MagicMock(rpm_used=1, rpm_limit=30, rpd_used=1, rpd_limit=500),
            start_time=__import__("time").time(),
            request_id="req-1",
            current_user=AuthenticatedUser(user_id="u1", claims={}),
            db=mock_db,
        )
    ]
    done = next(event for event in events if event.startswith("event: done"))
    return json.loads(done.split("data: ", 1)[1])["metadata"], recorded


def _state(**overrides):
    return {
        "user_input": "um", "learner_profile": {"level": "B1"}, "conversation_history": [],
        "diagnosis_errors": [], "diagnosis_intent": "ask", "retrieved_context": "", "retrieval_trace": [],
        "grammar_score": 0.8, "fluency_score": 0.8, "vocabulary_level": "B1",
        "cache_hit": False, "cache_policy": "on", "strategy": "praise",
        "diagnosis_usage": {"prompt_tokens": 200, "completion_tokens": 30, "cached_tokens": 0},
        **overrides,
    }


@pytest.fixture
def mock_db():
    db = MagicMock()
    collection = MagicMock()
    collection.find_one = AsyncMock(return_value=None)
    collection.update_one = AsyncMock()
    collection.insert_many = AsyncMock()
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=[])
    collection.find.return_value = cursor
    db.__getitem__.side_effect = lambda _name: collection
    return db


@pytest.fixture(autouse=True)
def _store(monkeypatch):
    import api.services.lexi_chat_service as svc

    store = MagicMock()
    for name in ("has_session", "get_messages", "set_session", "get_session", "append_message", "init_messages"):
        setattr(store, name, AsyncMock(return_value=None))
    monkeypatch.setattr(svc, "lexi_store", store)


@pytest.mark.asyncio
async def test_miss_reports_diagnosis_plus_generation_tokens_once(mock_db, monkeypatch):
    info = {
        "provider": "groq", "model": "qwen/qwen3.8-27b",
        "usage": {"prompt_tokens": 900, "completion_tokens": 60, "cached_tokens": 0, "source": "provider"},
    }

    meta, recorded = await _stream(_state(), mock_db, monkeypatch, provider_info=info)

    assert meta["usage"] == {"prompt_tokens": 1100, "completion_tokens": 90, "cached_tokens": 0, "source": "provider"}
    assert meta["cache_layer"] == "none" and meta["cache_bypass"] == ""
    assert meta["ttft_ms"] >= 0 and meta["first_chunk_ms"] >= meta["ttft_ms"]
    assert len(recorded) == 1
    row = recorded[0]
    assert (row["prompt_tokens"], row["completion_tokens"], row["usage_source"]) == (1100, 90, "provider")
    assert row["latency_ms"] == meta["latency_ms"] and row["ttft_ms"] == meta["ttft_ms"]


@pytest.mark.asyncio
async def test_cache_hit_costs_only_the_diagnosis(mock_db, monkeypatch):
    state = _state(cache_hit=True, cache_layer="L0", tutor_response="Cached reply")

    meta, recorded = await _stream(state, mock_db, monkeypatch)

    assert meta["cache_layer"] == "L0"
    assert meta["usage"] == {"prompt_tokens": 200, "completion_tokens": 30, "cached_tokens": 0, "source": "provider"}
    assert recorded[0]["cache_hit"] is True and recorded[0]["cache_layer"] == "L0"


@pytest.mark.asyncio
async def test_personal_facts_name_the_cache_bypass(mock_db, monkeypatch):
    meta, recorded = await _stream(_state(), mock_db, monkeypatch, card_facts="XP: 120")

    assert meta["cache_bypass"] == "facts"
    assert recorded[0]["cache_bypass"] == "facts"


@pytest.mark.asyncio
async def test_l1_shadow_similarity_is_reported(mock_db, monkeypatch):
    state = _state(l1_shadow_response="Fresh answer")

    meta, recorded = await _stream(state, mock_db, monkeypatch)

    assert meta["l1_shadow_f1"] == 1.0
    assert recorded[0]["l1_shadow_f1"] == 1.0
