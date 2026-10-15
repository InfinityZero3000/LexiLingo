"""A turn without a user_id must still get dense evidence.

V3PipelineContext.user_id is a required str while analyze()'s is Optional, so
building the context from a None user_id raised a pydantic ValidationError
inside the vector stage. The broad except there reported it as
"RetrievalServiceV3 unavailable" and fell through to a gateway that returned
nothing, so every anonymous turn lost the dense stage without an error.
"""
from __future__ import annotations

from unittest.mock import AsyncMock

import pytest

import api.services.trace_cag.retrieve as retrieve_mod
from api.models.v3_schemas import RetrievalBundleV3, VectorHit


class _KGService:
    def query_concepts(self, query, learner_level="B1", top_k=8):
        return []


class _RetrievalV3:
    def __init__(self):
        self.contexts = []

    async def retrieve(self, user_input, seed_nodes, ctx):
        self.contexts.append(ctx)
        return RetrievalBundleV3(
            query=user_input,
            vector_hits=[VectorHit(id="vec:1", score=0.8, snippet="dense evidence")],
        )


@pytest.mark.asyncio
async def test_anonymous_turn_still_reaches_the_vector_stage(monkeypatch):
    service = _RetrievalV3()
    monkeypatch.setattr("api.services.kg_service_v3.get_kg_service", lambda: _KGService())
    monkeypatch.setattr(retrieve_mod, "_get_retrieval_v3", AsyncMock(return_value=service))
    monkeypatch.setattr(retrieve_mod, "_kg_cache_get", lambda key: None)
    monkeypatch.setattr(retrieve_mod, "_kg_cache_set", lambda key, data: None)

    result = await retrieve_mod.retrieve_node({
        "user_input": "I would like to practise booking a hotel room.",
        "session_id": "session-anon",
        "user_id": None,
        "retrieval_policy": "rapid",
        "learner_profile": {"level": "B1"},
        "conversation_history": [],
        "diagnosis_root_causes": [],
        "diagnosis_errors": [],
        "diagnosis_confidence": 0.9,
        "kg_seed_concepts": ["concept:hotel"],
        "kg_expanded_nodes": [],
    })

    assert service.contexts, "vector stage never ran"
    assert service.contexts[0].user_id == ""
    texts = " ".join(item.get("text", "") for item in result["retrieval_trace"])
    assert "dense evidence" in texts
