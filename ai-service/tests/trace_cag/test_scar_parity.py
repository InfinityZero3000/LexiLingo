from api.services.trace_cag.l1_state_cache import (
    SCAR_WEIGHTS,
    L1Candidate,
    L1Request,
    decide_l1_reuse,
)
from service.tracecag_service.core import scar_l1 as portable_scar


def _request(**changes):
    values = dict(
        query_norm="who founded exampleco?", intent="ask", level="B1",
        profile_epoch=1, session_turn=0, concepts={"exampleco", "founder"},
        answer_target="person", relation_hints={"founder"}, evidence_hash="ev1",
        policy_version="p1", kg_version="kg1", source_version="s1",
        freshness_class="static",
    )
    values.update(changes)
    return L1Request(**values)


def _candidate(**changes):
    values = dict(
        cache_key="k1", query_norm="who established exampleco?", intent="ask",
        level="B1", profile_epoch=1, session_turn=0,
        concepts={"exampleco", "founder"}, answer_target="person",
        relation_hints={"founder"}, evidence_hash="ev1", policy_version="p1",
        kg_version="kg1", source_version="s1", freshness_class="static",
        created_at=100.0, ttl=1000,
    )
    values.update(changes)
    return L1Candidate(**values)


def test_scar_weights_are_frozen_and_sum_to_one():
    assert SCAR_WEIGHTS == {
        "intent": 0.20, "concept": 0.30, "relation": 0.15,
        "evidence": 0.20, "state_staleness": 0.15,
    }
    assert sum(SCAR_WEIGHTS.values()) == 1.0


def test_portable_service_uses_canonical_decision_function():
    assert portable_scar.decide_l1_reuse is decide_l1_reuse


def test_hard_gate_cannot_be_overridden_by_soft_score():
    decision = decide_l1_reuse(_request(policy_version="p2"), _candidate(), now=100.0)
    assert decision.risk == 0.15
    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert "mismatch:policy_version" in decision.reasons
