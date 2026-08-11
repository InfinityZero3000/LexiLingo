"""Unit tests for the SCAR-L1 state-certified reuse decision layer."""

import time

from api.services.trace_cag.l1_state_cache import (
    L1Candidate,
    L1Request,
    decide_l1_reuse,
)


def _request(**overrides):
    base = {
        "query_norm": "who founded the company that makes the iphone?",
        "intent": "ask",
        "level": "B1",
        "profile_epoch": 42,
        "session_turn": 0,
        "concepts": {"iphone", "apple inc"},
        "entities": {"iphone", "apple inc"},
        "answer_target": "person",
        "relation_hints": {"founder", "maker"},
        "evidence_hash": "ev:iphone:apple",
        "policy_version": "policy_v1",
        "kg_version": "kg_v1",
    }
    base.update(overrides)
    return L1Request(**base)


def _candidate(**overrides):
    base = {
        "cache_key": "cached-1",
        "query_norm": "who was the founder of the corporation behind the iphone?",
        "intent": "ask",
        "level": "B1",
        "profile_epoch": 42,
        "session_turn": 0,
        "concepts": {"iphone", "apple inc"},
        "entities": {"iphone", "apple inc"},
        "answer_target": "person",
        "relation_hints": {"founder", "maker"},
        "evidence_hash": "ev:iphone:apple",
        "policy_version": "policy_v1",
        "kg_version": "kg_v1",
        "created_at": time.time(),
        "ttl": 3600,
    }
    base.update(overrides)
    return L1Candidate(**base)


def test_l1_reuse_for_exact_state_match():
    request = _request(query_norm="who founded the company that makes the iphone?")
    candidate = _candidate(query_norm="who founded the company that makes the iphone?")

    decision = decide_l1_reuse(request, candidate)

    assert decision.decision == "reuse"
    assert decision.safe_to_reuse is True
    assert decision.risk <= 0.25


def test_l1_patch_for_safe_paraphrase():
    decision = decide_l1_reuse(_request(), _candidate())

    assert decision.decision == "patch"
    assert decision.safe_to_reuse is True
    assert decision.risk <= 0.55
    assert "state_compatible_near_hit" in decision.reasons


def test_l1_full_for_answer_target_shift():
    candidate = _candidate(answer_target="time")

    decision = decide_l1_reuse(_request(), candidate)

    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert "mismatch:answer_target" in decision.reasons


def test_l1_full_for_relation_shift():
    candidate = _candidate(relation_hints={"release_year"})

    decision = decide_l1_reuse(_request(), candidate)

    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert "mismatch:relation_path" in decision.reasons


def test_l1_full_for_level_shift():
    candidate = _candidate(level="A2")

    decision = decide_l1_reuse(_request(), candidate)

    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert "mismatch:level" in decision.reasons


def test_l1_full_for_profile_epoch_shift():
    candidate = _candidate(profile_epoch=99)

    decision = decide_l1_reuse(_request(), candidate)

    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert "mismatch:profile_epoch" in decision.reasons


def test_l1_full_for_low_concept_overlap():
    candidate = _candidate(concepts={"facebook", "mark zuckerberg"}, entities={"facebook"})

    decision = decide_l1_reuse(_request(), candidate)

    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert "concept_overlap_below_floor" in decision.reasons


def test_l1_full_for_stale_candidate():
    candidate = _candidate(created_at=time.time() - 7200, ttl=3600)

    decision = decide_l1_reuse(_request(), candidate)

    assert decision.decision == "full"
    assert decision.safe_to_reuse is False
    assert "stale_candidate" in decision.reasons
