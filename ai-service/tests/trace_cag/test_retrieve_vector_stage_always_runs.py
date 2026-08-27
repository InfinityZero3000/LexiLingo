"""The vector stage must run for a clean, confident turn under rapid policy.

It used to be skipped exactly there — the learner writes correct English, the
diagnosis is confident, and the tutor is left with query_concepts as its only
source of KG evidence. Lexical finds a topic when the learner names it; over
120 learner-phrased queries it put on-topic material in the top 5 for 55.8%,
against 90.8% for the dense stage.
"""
from __future__ import annotations

import uuid
from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.retrieve as retrieve_mod
from api.models.v3_schemas import RetrievalBundleV3, VectorHit


class _KGService:
    def query_concepts(self, query, learner_level="B1", top_k=8):
        return [{"id": "kg:concept.1", "title": "KG Concept", "keywords": "kg", "score": 0.5}]


class _RetrievalV3:
    def __init__(self):
        self.calls = 0

    async def retrieve(self, user_input, seed_nodes, ctx):
        self.calls += 1
        return RetrievalBundleV3(
            query=user_input,
            vector_hits=[VectorHit(id="vec:1", score=0.8, snippet="vector evidence")],
        )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "errors, confidence",
    [
        ([], 0.95),  # the case the old short-circuit killed
        ([], 0.5),
        ([{"span": "go", "correction": "went"}], 0.9),
    ],
)
async def test_rapid_policy_still_runs_the_vector_stage(monkeypatch, errors, confidence):
    service = _RetrievalV3()
    monkeypatch.setattr("api.services.kg_service_v3.get_kg_service", lambda: _KGService())
    monkeypatch.setattr(retrieve_mod, "_get_retrieval_v3", AsyncMock(return_value=service))
    monkeypatch.setattr(retrieve_mod, "_kg_cache_get", lambda key: None)
    monkeypatch.setattr(retrieve_mod, "_kg_cache_set", lambda key, data: None)

    state = {
        "user_input": f"I would like to practise booking a hotel room. {uuid.uuid4()}",
        "session_id": "session-vector-stage",
        "user_id": "user-1",
        "retrieval_policy": "rapid",
        "learner_profile": {"level": "B1"},
        "conversation_history": [],
        "diagnosis_root_causes": ["concept:present_perfect", "concept:auxiliary_verbs"],
        "diagnosis_errors": errors,
        "diagnosis_confidence": confidence,
        "kg_seed_concepts": ["concept:present_perfect"],
        "kg_expanded_nodes": [],
    }

    result = await retrieve_mod.retrieve_node(state)

    assert service.calls == 1, "vector stage did not run"
    texts = " ".join(item.get("text", "") for item in result["retrieval_trace"])
    assert "vector evidence" in texts
