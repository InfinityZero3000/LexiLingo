"""Tier-1 topic routing: gate, membership, and what it removes from the prompt.

A learner turn either names one of the graph's topics or it does not, and the
two are separable — over 120 topic phrasings the best topic similarity has
median 0.550, over 120 grammar/idiom questions drawn from the graph itself it
has median 0.180. Routed turns draw the whole prompt from the matched topics'
subgraphs; everything else keeps the corpus-wide path, because lexical
retrieval is what answers grammar and idiom questions.
"""
from __future__ import annotations

from unittest.mock import AsyncMock

import numpy as np
import pytest

import api.services.retrieval_service_v3 as rs_module
import api.services.trace_cag.retrieve as retrieve_mod
from api.models.v3_schemas import RetrievalBundleV3, VectorHit


class _Embedder:
    """Two clusters: 'hotel' words point one way, 'grammar' words the other."""

    def embed_texts(self, texts):
        return np.stack([self._one(t) for t in texts])

    def embed_text(self, text):
        return self._one(text)

    @staticmethod
    def _one(text):
        low = (text or "").lower()
        vec = np.array([
            float("hotel" in low or "check in" in low or "room" in low),
            float("tense" in low or "article" in low or "grammar" in low),
            0.1,
        ], dtype=np.float32)
        return vec / (np.linalg.norm(vec) or 1.0)


@pytest.fixture()
def service(monkeypatch):
    svc = rs_module.RetrievalServiceV3.__new__(rs_module.RetrievalServiceV3)
    svc.config = rs_module.RetrievalConfig()
    svc.embedder = _Embedder()
    svc._concept_cache = {
        "topic:hotel_check_in": {"title": "Hotel Check In", "keywords": "hotel room", "level": "A2"},
        "phrase:hotel_key": {"title": "Could I have my room key", "keywords": "hotel room", "level": "A2"},
        "function:hotel_ask": {"title": "Asking at the hotel desk", "keywords": "hotel", "level": "A2"},
        "concept:grammar.articles": {"title": "When to use the article a", "keywords": "grammar article", "level": "B1"},
    }
    svc._concept_embeddings = {
        cid: _Embedder._one(f"{m['title']} {m['keywords']}")
        for cid, m in svc._concept_cache.items()
    }
    svc._topic_ids = []
    svc._topic_matrix = None
    svc._refresh_topic_index()

    class _KG:
        def get_concepts(self_inner):
            return svc._concept_cache

        def get_topic_members(self_inner):
            return {"topic:hotel_check_in": ["phrase:hotel_key", "function:hotel_ask"]}

        async def expand(self_inner, seed_nodes, hops=1):
            from api.models.v3_schemas import KGHits
            return KGHits(seed_nodes=list(seed_nodes), expanded_nodes=[], paths=[])

    svc.kg = _KG()
    return svc


def test_topic_query_routes_to_its_topic(service):
    topics, sim = service.route_to_topics("I want to practise hotel check in")
    assert topics[:1] == ["topic:hotel_check_in"]
    assert sim >= rs_module._TOPIC_ROUTE_MIN_SIM


def test_grammar_question_is_not_routed(service):
    topics, sim = service.route_to_topics("When do I use the article a in this tense")
    assert topics == []
    assert sim < rs_module._TOPIC_ROUTE_MIN_SIM


@pytest.mark.asyncio
async def test_routed_retrieval_draws_only_from_the_topic_subgraph(service):
    from api.models.v3_schemas import V3PipelineContext

    bundle = await service.retrieve(
        "hotel room check in",
        [],
        V3PipelineContext(user_input="hotel room check in", session_id="s", user_id="u"),
    )
    assert bundle.routed_topics == ["topic:hotel_check_in"]
    members = {"phrase:hotel_key", "function:hotel_ask"}
    assert {h.id for h in bundle.vector_hits} <= members


class _RetrievalV3:
    def __init__(self, routed):
        self.routed = routed

    async def retrieve(self, user_input, seed_nodes, ctx):
        return RetrievalBundleV3(
            query=user_input,
            vector_hits=[VectorHit(id="phrase:hotel_key", score=0.9, snippet="room key")],
            routed_topics=list(self.routed),
        )


class _KGService:
    def query_concepts(self, query, learner_level="B1", top_k=8):
        return [{"id": "concept:noise", "title": "Unrelated", "keywords": "x", "score": 0.9}]


async def _run(monkeypatch, routed):
    monkeypatch.setattr("api.services.kg_service_v3.get_kg_service", lambda: _KGService())
    monkeypatch.setattr(retrieve_mod, "_get_retrieval_v3",
                        AsyncMock(return_value=_RetrievalV3(routed)))
    monkeypatch.setattr(retrieve_mod, "_kg_cache_get", lambda key: None)
    monkeypatch.setattr(retrieve_mod, "_kg_cache_set", lambda key, data: None)
    return await retrieve_mod.retrieve_node({
        "user_input": "I would like to practise checking in to a hotel.",
        "session_id": "s", "user_id": "u", "retrieval_policy": "rapid",
        "learner_profile": {"level": "B1"}, "conversation_history": [],
        "diagnosis_root_causes": [], "diagnosis_confidence": 0.9,
        "diagnosis_errors": [{"span": "go", "correction": "went", "explanation": "past"}],
        "kg_seed_concepts": ["concept:hotel"],
        "kg_expanded_nodes": [{"id": "concept:far", "relation": "related_to",
                               "title": "Something Else", "keywords": "unrelated"}],
    })


@pytest.mark.asyncio
async def test_routed_turn_drops_lexical_and_expanded_evidence(monkeypatch):
    result = await _run(monkeypatch, ["topic:hotel_check_in"])
    ids = [item["item_id"] for item in result["retrieval_trace"]]
    assert "phrase:hotel_key" in ids
    assert "concept:noise" not in ids, "lexical evidence survived a routed turn"
    assert "concept:far" not in ids, "expanded evidence survived a routed turn"
    # the learner's own correction is not retrieval and must stay
    texts = " ".join(item["text"] for item in result["retrieval_trace"])
    assert "'go' → 'went'" in texts
    assert result["retrieval_meta"]["topic_routing"]["routed"] is True


@pytest.mark.asyncio
async def test_unrouted_turn_keeps_every_stage(monkeypatch):
    result = await _run(monkeypatch, [])
    ids = [item["item_id"] for item in result["retrieval_trace"]]
    assert "concept:noise" in ids
    assert result["retrieval_meta"]["topic_routing"]["routed"] is False


@pytest.mark.asyncio
async def test_learner_overlay_keeps_the_turns_own_corrections(monkeypatch):
    """rank_with_learner_overlay drops candidates with no concept_id, and
    production runs LEARNER_STATE_MODE=read — diagnosis evidence carried no
    item_id, so every grammar correction was deleted before the prompt."""
    from api.core.config import settings

    monkeypatch.setattr(settings, "LEARNER_STATE_MODE", "read")
    result = await _run(monkeypatch, [])
    texts = " ".join(item["text"] for item in result["retrieval_trace"])
    assert "'go' → 'went'" in texts
