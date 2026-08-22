from unittest.mock import AsyncMock

import pytest

from api.services.trace_cag.dependencies import DependencyEvent, compile_dependency_trace


def test_compile_dependency_trace_deduplicates_and_sorts():
    events = [
        DependencyEvent("policy:tutor", "policy", "v2", "prompt-registry"),
        DependencyEvent("learner:u1:profile", "learner", "7", "learner-state"),
        DependencyEvent("policy:tutor", "policy", "v2", "prompt-registry"),
    ]

    assert compile_dependency_trace(events) == (
        DependencyEvent("learner:u1:profile", "learner", "7", "learner-state"),
        DependencyEvent("policy:tutor", "policy", "v2", "prompt-registry"),
    )


def test_compile_dependency_trace_rejects_conflicting_versions():
    with pytest.raises(ValueError, match="conflicting dependency versions"):
        compile_dependency_trace([
            DependencyEvent("kg:main", "kg", "v1", "kuzu"),
            DependencyEvent("kg:main", "kg", "v2", "kuzu"),
        ])


def test_compile_dependency_trace_rejects_missing_required_token():
    with pytest.raises(ValueError, match="missing required dependency token"):
        compile_dependency_trace([
            DependencyEvent("source:qa", "source", "", "dataset", required=True),
        ])


def test_compile_dependency_trace_allows_missing_optional_token():
    assert compile_dependency_trace([
        DependencyEvent("source:optional", "source", "", "dataset", required=False),
    ]) == (
        DependencyEvent("source:optional", "source", "", "dataset", required=False),
    )


class _FixedKGService:
    def query_concepts(self, query, learner_level="B1", top_k=8):
        return [{"id": "kg:concept.1", "title": "KG Concept", "keywords": "kg", "score": 0.5}]


@pytest.mark.asyncio
async def test_evidence_dependency_key_scoped_by_retrieval_policy(monkeypatch):
    """Regression for the "one mode poisons another mode's cache" bug: two
    modes retrieving different top-k evidence for the SAME question (e.g.
    cag_vanilla's "full" vs tracecag_rapid's "rapid" retrieval_policy) must not
    share an "evidence:retrieval:query:<hash>" dependency key. Before the fix,
    query_scope hashed only the question text, so observe_dependency_tokens's
    setdefault let whichever mode ran first lock the token — every other
    mode's later cache-freshness recheck for that question then failed
    (measured live: tracecag_rapid Hit dropped from ~47% to ~6% when run right
    after cag_vanilla over the same question set)."""
    import api.services.trace_cag.retrieve as retrieve_mod

    monkeypatch.setattr("api.services.kg_service_v3.get_kg_service", lambda: _FixedKGService())
    monkeypatch.setattr(retrieve_mod, "_get_retrieval_v3", AsyncMock(return_value=None))
    monkeypatch.setattr(retrieve_mod, "_kg_cache_get", lambda key: None)
    monkeypatch.setattr(retrieve_mod, "_kg_cache_set", lambda key, data: None)

    def base_state(retrieval_policy: str) -> dict:
        return {
            "user_input": "Which director made the film Ed Wood?",
            "session_id": "session-scope-test",
            "user_id": "user-1",
            "retrieval_policy": retrieval_policy,
            "learner_profile": {"level": "B1"},
            "conversation_history": [],
            "diagnosis_root_causes": ["concept:present_perfect"],
            "diagnosis_errors": [],
            "diagnosis_confidence": 0.5,
            "kg_seed_concepts": ["concept:present_perfect"],
            "kg_expanded_nodes": [],
        }

    full_result = await retrieve_mod.retrieve_node(base_state("full"))
    rapid_result = await retrieve_mod.retrieve_node(base_state("rapid"))

    def evidence_key(result: dict) -> str:
        events = result["dependency_events"]
        matches = [e["key"] for e in events if e["key"].startswith("evidence:retrieval:")]
        assert matches, "retrieve_node must always emit an evidence:retrieval: dependency"
        return matches[0]

    assert evidence_key(full_result) != evidence_key(rapid_result), (
        "different retrieval_policy values for the same question must not "
        "share a dependency key — otherwise setdefault-based token tracking "
        "lets one mode's cache writes invalidate another mode's"
    )
