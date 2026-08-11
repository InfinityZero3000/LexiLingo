from __future__ import annotations

import asyncio
import time
import uuid
from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.retrieve as retrieve_mod
from api.models.v3_schemas import RetrievalBundleV3, VectorHit

STAGE_DELAY_S = 0.2


class _SlowKGService:
    """Stands in for get_kg_service() — a synchronous, blocking call (like
    the real query_concepts) so the test proves Stage 1 no longer starves
    Stage 2 of the event loop."""

    def query_concepts(self, query, learner_level="B1", top_k=8):
        time.sleep(STAGE_DELAY_S)
        return [{"id": "kg:concept.1", "title": "KG Concept", "keywords": "kg", "score": 0.5}]


class _SlowRetrievalV3:
    async def retrieve(self, user_input, seed_nodes, ctx):
        await asyncio.sleep(STAGE_DELAY_S)
        return RetrievalBundleV3(
            query=user_input,
            vector_hits=[VectorHit(id="vec:1", score=0.8, snippet="vector evidence")],
        )


@pytest.mark.asyncio
async def test_kg_and_vector_stages_run_concurrently_not_sequentially(monkeypatch):
    """Both stages take STAGE_DELAY_S on their own — if retrieve_node still
    ran them sequentially, this would take >= 2 * STAGE_DELAY_S. Overlapped,
    it should take roughly max(STAGE_DELAY_S, STAGE_DELAY_S) plus overhead."""
    monkeypatch.setattr(
        "api.services.kg_service_v3.get_kg_service", lambda: _SlowKGService()
    )
    monkeypatch.setattr(retrieve_mod, "_get_retrieval_v3", AsyncMock(return_value=_SlowRetrievalV3()))
    monkeypatch.setattr(retrieve_mod, "_kg_cache_get", lambda key: None)
    monkeypatch.setattr(retrieve_mod, "_kg_cache_set", lambda key, data: None)

    unique_query = f"How do I use the present perfect tense? {uuid.uuid4()}"
    state = {
        "user_input": unique_query,
        "session_id": "session-overlap-test",
        "user_id": "user-1",
        "retrieval_policy": "full",
        "learner_profile": {"level": "B1"},
        "conversation_history": [],
        # Enough Stage-1 evidence to stay >= 3 items after Stage 2 merges in,
        # so Stage 3 (L2 external search) doesn't also fire and pull in a
        # real embedding-model load — this test is only about Stage 1/2 overlap.
        "diagnosis_root_causes": ["concept:present_perfect", "concept:auxiliary_verbs"],
        "diagnosis_errors": [],
        "diagnosis_confidence": 0.5,
        "kg_seed_concepts": ["concept:present_perfect"],
        "kg_expanded_nodes": [],
    }

    started = time.monotonic()
    result = await retrieve_mod.retrieve_node(state)
    elapsed = time.monotonic() - started

    assert elapsed < STAGE_DELAY_S * 1.7, (
        f"retrieve_node took {elapsed:.3f}s — Stage 1 (KG) and Stage 2 (vector) "
        f"appear to be running sequentially, not concurrently"
    )

    evidence = result["retrieval_trace"]
    texts = " ".join(item.get("text", "") for item in evidence)
    assert "KG Concept" in texts, "KG-stage evidence missing from result"
    assert "vector evidence" in texts, "Vector-stage evidence missing from result"


@pytest.mark.asyncio
async def test_get_retrieval_v3_dedupes_concurrent_construction(monkeypatch):
    """RetrievalServiceV3's constructor takes ~170s on the real KG (measured
    live), so it's warmed as a background task at boot instead of blocking
    startup — meaning a live request can legitimately race the still-running
    warmup. The lock in _get_retrieval_v3() must make that request await the
    same in-flight build rather than starting a second, redundant one."""
    monkeypatch.setattr(retrieve_mod, "_retrieval_v3_instance", None)
    monkeypatch.setattr(retrieve_mod, "_retrieval_v3_lock", asyncio.Lock())

    build_calls = 0

    def fake_retrieval_v3_ctor(kg):
        nonlocal build_calls
        build_calls += 1
        time.sleep(STAGE_DELAY_S)
        return object()

    import api.services.kg_service_v3 as kg_service_mod
    import api.services.retrieval_service_v3 as retrieval_service_mod

    monkeypatch.setattr(kg_service_mod, "get_kg_service", lambda: object())
    monkeypatch.setattr(retrieval_service_mod, "RetrievalServiceV3", fake_retrieval_v3_ctor)

    results = await asyncio.gather(
        *(retrieve_mod._get_retrieval_v3() for _ in range(5))
    )

    assert build_calls == 1, "concurrent callers built RetrievalServiceV3 more than once"
    assert len({id(r) for r in results}) == 1, "concurrent callers got different instances"
