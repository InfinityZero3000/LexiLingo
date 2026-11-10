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

    future = decide_l1_reuse(_request(), _candidate(schema_version=5), now=101.0)
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


TTL = 3600


def _aged(fraction, **candidate):
    return _candidate(created_at=100.0, ttl=TTL, **candidate), 100.0 + fraction * TTL


def test_asymmetric_evidence_adds_no_risk():
    candidate, now = _aged(0.0)
    decision = decide_l1_reuse(_request(evidence_hash=""), candidate, now=now)
    assert decision.decision == "reuse"
    assert decision.risk == pytest.approx(0.0)


def test_unverified_evidence_age_boundary():
    at_edge, now = _aged(1 / 3)
    assert decide_l1_reuse(_request(evidence_hash=""), at_edge, now=now).decision == "reuse"

    past_edge, now = _aged(1 / 3 + 0.01)
    decision = decide_l1_reuse(_request(evidence_hash=""), past_edge, now=now)
    assert decision.decision == "full"
    assert "unverified_evidence_age" in decision.reasons


@pytest.mark.parametrize("declared", [True, False])
def test_symmetric_mismatched_evidence_still_blocked(declared):
    required = set(BASE_REQUIRED_DIMENSIONS) | ({"evidence_hash"} if declared else set())
    candidate, now = _aged(0.0, evidence_hash="ev_old", required_dimensions=required)
    decision = decide_l1_reuse(_request(evidence_hash="ev_new", required_dimensions=required), candidate, now=now)
    assert decision.decision == "full"
    assert "mismatch:evidence_hash" in decision.reasons


def test_no_evidence_dependency_has_no_age_cap():
    candidate, now = _aged(0.9, evidence_hash="")
    decision = decide_l1_reuse(_request(evidence_hash=""), candidate, now=now)
    assert decision.decision == "reuse"
    assert "unverified_evidence_age" not in decision.reasons


def test_post_pcc_risk_bounds():
    """Fixes the argument that tau_patch (0.55) and, for same-query reuse, tau_reuse (0.25) never bind after the PCC."""
    served = 0
    for overlap in (0.5, 0.6, 0.75, 1.0):
        request_concepts = {f"c{i}" for i in range(4)}
        shared = round(overlap * 4)
        candidate_concepts = {f"c{i}" for i in range(shared)} | {f"x{i}" for i in range(4 - shared)}
        if len(request_concepts & candidate_concepts) / len(request_concepts | candidate_concepts) < 0.5:
            continue
        for age in (0.0, 0.1, 0.2, 1 / 3, 0.5, 0.9, 0.99):
            for request_evidence in ("", "ev_v1"):
                for query in ("who founded exampleco?", "who started exampleco?"):
                    request = _request(concepts=request_concepts, evidence_hash=request_evidence)
                    candidate, now = _aged(age, concepts=candidate_concepts, query_norm=query)
                    decision = decide_l1_reuse(request, candidate, now=now)
                    if decision.decision == "full":
                        continue
                    served += 1
                    assert decision.risk < 0.30, (overlap, age, request_evidence, decision)
                    # Same query_norm means identical concepts in production (J=1); only then is reuse bounded by 0.15.
                    if decision.decision == "reuse" and overlap == 1.0:
                        assert decision.risk <= 0.15, (overlap, age, request_evidence, decision)
    assert served
