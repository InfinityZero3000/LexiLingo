import pytest

from api.services.trace_cag.l1_state_cache import (
    BASE_REQUIRED_DIMENSIONS,
    L1Candidate,
    L1Request,
    decide_l1_reuse,
)


def _request(**overrides):
    data = {
        "query_norm": "who founded exampleco?",
        "intent": "ask",
        "level": "B1",
        "profile_epoch": 1,
        "session_turn": 0,
        "concepts": {"exampleco", "founder"},
        "entities": {"exampleco"},
        "answer_target": "person",
        "relation_hints": {"founder"},
        "evidence_hash": "ev_v1",
        "policy_version": "policy_v1",
        "kg_version": "kg_v1",
        "source_version": "src_v1",
        "freshness_class": "static",
        "native_language": "Vietnamese",
    }
    data.update(overrides)
    return L1Request(**data)


def _candidate(**overrides):
    data = {
        "cache_key": "k1",
        "query_norm": "who founded exampleco?",
        "intent": "ask",
        "level": "B1",
        "profile_epoch": 1,
        "session_turn": 0,
        "concepts": {"exampleco", "founder"},
        "entities": {"exampleco"},
        "answer_target": "person",
        "relation_hints": {"founder"},
        "evidence_hash": "ev_v1",
        "policy_version": "policy_v1",
        "kg_version": "kg_v1",
        "source_version": "src_v1",
        "freshness_class": "static",
        "native_language": "Vietnamese",
        "created_at": 100.0,
        "ttl": 3600,
    }
    data.update(overrides)
    return L1Candidate(**data)


def test_l1_certificate_rejects_source_and_policy_drift():
    decision = decide_l1_reuse(
        _request(source_version="src_v2"),
        _candidate(),
        now=101.0,
    )
    assert decision.decision == "full"
    assert "mismatch:source_version" in decision.reasons

    decision = decide_l1_reuse(
        _request(policy_version="policy_v2"),
        _candidate(),
        now=101.0,
    )
    assert decision.decision == "full"
    assert "mismatch:policy_version" in decision.reasons


def test_l1_certificate_rejects_missing_required_dimension_and_schema_v1():
    missing = decide_l1_reuse(
        _request(evidence_hash=""),
        _candidate(required_dimensions={"intent", "level", "profile_epoch", "policy_version", "kg_version", "answer_target", "evidence_hash"}),
        now=101.0,
    )
    assert missing.decision == "full"
    assert "missing_required:evidence_hash" in missing.reasons

    legacy = decide_l1_reuse(_request(), _candidate(schema_version=2), now=101.0)
    assert legacy.decision == "full"
    assert legacy.reasons == ("unsupported_certificate_schema",)

    future = decide_l1_reuse(_request(), _candidate(schema_version=4), now=101.0)
    assert future.decision == "full"
    assert future.reasons == ("unsupported_certificate_schema",)


def test_request_dependency_cannot_be_omitted_by_candidate():
    decision = decide_l1_reuse(
        _request(required_dimensions={"evidence_hash"}),
        _candidate(evidence_hash="", required_dimensions=set()),
        now=101.0,
    )
    assert decision.decision == "full"
    assert "missing_required:evidence_hash" in decision.reasons


@pytest.mark.parametrize("dimension", sorted(BASE_REQUIRED_DIMENSIONS))
@pytest.mark.parametrize("side", ["request", "candidate"])
def test_every_base_dimension_is_fail_closed_on_both_sides(dimension, side):
    # profile_epoch is an integer and zero is a valid epoch, so None represents
    # an absent value in a malformed/legacy payload.
    missing = None if dimension == "profile_epoch" else ""
    request = _request(**({dimension: missing} if side == "request" else {}))
    candidate = _candidate(**({dimension: missing} if side == "candidate" else {}))

    decision = decide_l1_reuse(request, candidate, now=101.0)

    assert decision.decision == "full"
    assert f"missing_required:{dimension}" in decision.reasons


@pytest.mark.parametrize(
    "dimension,value",
    [
        ("evidence_hash", "ev_v1"),
        ("source_version", "src_v1"),
        ("freshness_class", "static"),
        ("relation_path", {"founder"}),
        ("native_language", "Vietnamese"),
    ],
)
def test_declared_dependency_is_fail_closed(dimension, value):
    required = set(BASE_REQUIRED_DIMENSIONS) | {dimension}
    request_field = "relation_hints" if dimension == "relation_path" else dimension
    request = _request(**{request_field: "" if isinstance(value, str) else set()})
    candidate = _candidate(required_dimensions=required)

    decision = decide_l1_reuse(request, candidate, now=101.0)

    assert decision.decision == "full"
    assert f"missing_required:{dimension}" in decision.reasons


def test_undeclared_optional_dimensions_may_be_absent():
    optional = {
        "evidence_hash": "",
        "source_version": "",
        "freshness_class": "",
        "relation_hints": set(),
        "native_language": "",
    }
    decision = decide_l1_reuse(
        _request(**optional),
        _candidate(**optional),
        now=101.0,
    )

    assert decision.decision == "reuse"
    assert decision.safe_to_reuse is True
