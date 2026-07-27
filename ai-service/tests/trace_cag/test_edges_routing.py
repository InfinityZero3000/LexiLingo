"""
Unit tests for TraceCAG edge routing functions.

Covers:
- route_after_diagnosis:  A1/A2 + errors → vietnamese_node
                          native_explanation_requested=True → vietnamese_node (any level)
                          low confidence → ask_clarify_node
                          otherwise → retrieve_node
- route_after_vietnamese: always → retrieve_node
"""

import pytest
from api.services.trace_cag.edges import route_after_diagnosis, route_after_vietnamese


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _state(level: str = "B1", confidence: float = 0.9, errors: list | None = None, native_requested: bool = False) -> dict:
    """Build a minimal TraceCAGState for routing tests."""
    return {
        "diagnosis_confidence": confidence,
        "learner_profile": {"level": level},
        "diagnosis_errors": errors if errors is not None else [],
        "native_explanation_requested": native_requested,
    }


_SAMPLE_ERROR = {"span": "go", "type": "verb_tense", "correction": "went", "explanation": "Past tense required"}


# ---------------------------------------------------------------------------
# route_after_diagnosis — Vietnamese branch
# ---------------------------------------------------------------------------

class TestVietnameseNodeRouting:
    """A1/A2 learners with errors must be bridged through the Vietnamese node."""

    def test_a1_with_errors_routes_to_vietnamese(self):
        assert route_after_diagnosis(_state("A1", errors=[_SAMPLE_ERROR])) == "vietnamese_node"

    def test_a2_with_errors_routes_to_vietnamese(self):
        assert route_after_diagnosis(_state("A2", errors=[_SAMPLE_ERROR])) == "vietnamese_node"

    def test_a1_with_multiple_errors_routes_to_vietnamese(self):
        errors = [_SAMPLE_ERROR, {"span": "yesterday", "type": "adverb_placement", "correction": "yesterday", "explanation": "Position"}]
        assert route_after_diagnosis(_state("A1", errors=errors)) == "vietnamese_node"

    def test_a2_with_multiple_errors_routes_to_vietnamese(self):
        errors = [_SAMPLE_ERROR, _SAMPLE_ERROR]
        assert route_after_diagnosis(_state("A2", errors=errors)) == "vietnamese_node"

    def test_a1_no_errors_skips_vietnamese(self):
        """Beginner with no errors → normal retrieve, not Vietnamese."""
        assert route_after_diagnosis(_state("A1", errors=[])) == "retrieve_node"

    def test_a2_no_errors_skips_vietnamese(self):
        assert route_after_diagnosis(_state("A2", errors=[])) == "retrieve_node"

    def test_a1_confidence_at_boundary_with_errors(self):
        """confidence == 0.5 is NOT low confidence — should still route to vietnamese."""
        assert route_after_diagnosis(_state("A1", confidence=0.5, errors=[_SAMPLE_ERROR])) == "vietnamese_node"

    def test_level_is_case_sensitive_lowercase_does_not_match(self):
        """Level 'a1' (lowercase) is NOT treated as A1 — falls through to retrieve."""
        assert route_after_diagnosis(_state("a1", errors=[_SAMPLE_ERROR])) == "retrieve_node"


# ---------------------------------------------------------------------------
# route_after_diagnosis — native_explanation_requested branch
# ---------------------------------------------------------------------------

class TestNativeExplicitRouting:
    """Explicit native-language request routes to vietnamese_node regardless of level."""

    @pytest.mark.parametrize("level", ["B1", "B2", "C1", "C2"])
    def test_explicit_request_overrides_intermediate_level(self, level):
        """Even B1+ learners get native hint when they explicitly request it."""
        assert route_after_diagnosis(_state(level, native_requested=True)) == "vietnamese_node"

    def test_explicit_request_overrides_advanced_with_no_errors(self):
        assert route_after_diagnosis(_state("C2", errors=[], native_requested=True)) == "vietnamese_node"

    def test_explicit_request_with_a1_and_errors(self):
        """Both conditions satisfied — still routes to vietnamese_node."""
        assert route_after_diagnosis(_state("A1", errors=[_SAMPLE_ERROR], native_requested=True)) == "vietnamese_node"

    def test_explicit_request_does_not_override_low_confidence(self):
        """Low confidence takes top priority — clarification before native hint."""
        assert route_after_diagnosis(_state("B1", confidence=0.3, native_requested=True)) == "ask_clarify_node"

    def test_no_explicit_request_b1_with_errors_stays_retrieve(self):
        """Without the flag, B1+ always goes to retrieve."""
        assert route_after_diagnosis(_state("B1", errors=[_SAMPLE_ERROR], native_requested=False)) == "retrieve_node"

    def test_flag_false_does_not_affect_a1_routing(self):
        """A1 with errors still routes correctly when flag is explicitly False."""
        assert route_after_diagnosis(_state("A1", errors=[_SAMPLE_ERROR], native_requested=False)) == "vietnamese_node"


# ---------------------------------------------------------------------------
# route_after_diagnosis — ask_clarify branch
# ---------------------------------------------------------------------------

class TestAskClarifyRouting:
    """confidence < 0.5 must always route to ask_clarify, regardless of level/errors."""

    def test_low_confidence_routes_to_clarify(self):
        assert route_after_diagnosis(_state(confidence=0.3)) == "ask_clarify_node"

    def test_very_low_confidence_routes_to_clarify(self):
        assert route_after_diagnosis(_state(confidence=0.0)) == "ask_clarify_node"

    def test_confidence_just_below_threshold_routes_to_clarify(self):
        assert route_after_diagnosis(_state(confidence=0.499)) == "ask_clarify_node"

    def test_a1_with_errors_but_low_confidence_routes_to_clarify(self):
        """Low confidence takes priority — even A1+errors must clarify first."""
        assert route_after_diagnosis(_state("A1", confidence=0.3, errors=[_SAMPLE_ERROR])) == "ask_clarify_node"

    def test_a2_with_errors_but_low_confidence_routes_to_clarify(self):
        assert route_after_diagnosis(_state("A2", confidence=0.1, errors=[_SAMPLE_ERROR])) == "ask_clarify_node"

    def test_confidence_exactly_0_5_is_not_low(self):
        """Boundary: 0.5 is NOT < 0.5, must not route to clarify."""
        result = route_after_diagnosis(_state("B1", confidence=0.5, errors=[]))
        assert result != "ask_clarify_node"

    def test_confidence_just_above_threshold_not_clarify(self):
        assert route_after_diagnosis(_state(confidence=0.501)) != "ask_clarify_node"


# ---------------------------------------------------------------------------
# route_after_diagnosis — normal retrieve branch
# ---------------------------------------------------------------------------

class TestNormalRetrieveRouting:
    """B1 and above, or beginners with no errors, always go to retrieve."""

    @pytest.mark.parametrize("level", ["B1", "B2", "C1", "C2"])
    def test_intermediate_advanced_with_errors_routes_to_retrieve(self, level):
        assert route_after_diagnosis(_state(level, errors=[_SAMPLE_ERROR])) == "retrieve_node"

    @pytest.mark.parametrize("level", ["B1", "B2", "C1", "C2"])
    def test_intermediate_advanced_no_errors_routes_to_retrieve(self, level):
        assert route_after_diagnosis(_state(level, errors=[])) == "retrieve_node"

    def test_default_confidence_routes_to_retrieve(self):
        """When confidence is missing, defaults to 1.0 → normal flow."""
        state = {"learner_profile": {"level": "B1"}, "diagnosis_errors": []}
        assert route_after_diagnosis(state) == "retrieve_node"

    def test_missing_learner_profile_defaults_to_retrieve(self):
        """When learner_profile is missing, level defaults to B1 → retrieve."""
        state = {"diagnosis_confidence": 0.9, "diagnosis_errors": []}
        assert route_after_diagnosis(state) == "retrieve_node"

    def test_missing_errors_field_defaults_to_retrieve(self):
        """When diagnosis_errors is missing, treated as empty → retrieve."""
        state = {"diagnosis_confidence": 0.9, "learner_profile": {"level": "A1"}}
        assert route_after_diagnosis(state) == "retrieve_node"


# ---------------------------------------------------------------------------
# route_after_diagnosis — complete decision matrix
# ---------------------------------------------------------------------------

class TestRoutingDecisionMatrix:
    """Parameterized matrix covering every branch combination."""

    @pytest.mark.parametrize("level,confidence,has_errors,native_requested,expected", [
        # --- Vietnamese branch: A1/A2 + errors ---
        ("A1", 0.9,  True,  False, "vietnamese_node"),
        ("A2", 0.9,  True,  False, "vietnamese_node"),
        ("A1", 0.5,  True,  False, "vietnamese_node"),   # boundary confidence
        ("A2", 0.5,  True,  False, "vietnamese_node"),
        # --- Vietnamese branch: explicit native request ---
        ("B1", 0.9,  False, True,  "vietnamese_node"),
        ("B2", 0.9,  True,  True,  "vietnamese_node"),
        ("C1", 0.9,  False, True,  "vietnamese_node"),
        ("A1", 0.9,  True,  True,  "vietnamese_node"),   # both conditions
        # --- Clarify branch (overrides everything) ---
        ("A1", 0.49, True,  False, "ask_clarify_node"),
        ("A2", 0.3,  True,  False, "ask_clarify_node"),
        ("B1", 0.1,  True,  False, "ask_clarify_node"),
        ("C2", 0.0,  False, False, "ask_clarify_node"),
        ("B1", 0.3,  False, True,  "ask_clarify_node"),  # explicit + low conf → clarify wins
        # --- Retrieve branch ---
        ("A1", 0.9,  False, False, "retrieve_node"),
        ("A2", 0.9,  False, False, "retrieve_node"),
        ("B1", 0.9,  True,  False, "retrieve_node"),
        ("B2", 0.9,  True,  False, "retrieve_node"),
        ("C1", 0.9,  False, False, "retrieve_node"),
        ("C2", 1.0,  False, False, "retrieve_node"),
    ])
    def test_routing_matrix(self, level, confidence, has_errors, native_requested, expected):
        errors = [_SAMPLE_ERROR] if has_errors else []
        state = _state(level=level, confidence=confidence, errors=errors, native_requested=native_requested)
        assert route_after_diagnosis(state) == expected


# ---------------------------------------------------------------------------
# route_after_vietnamese
# ---------------------------------------------------------------------------

class TestRouteAfterVietnamese:
    """After the Vietnamese bridge node, always continue to retrieve."""

    def test_always_routes_to_retrieve(self):
        assert route_after_vietnamese({}) == "retrieve_node"

    def test_routes_to_retrieve_regardless_of_state(self):
        full_state = _state("A1", confidence=0.9, errors=[_SAMPLE_ERROR])
        full_state["vietnamese_hint"] = "Bạn cần dùng thì quá khứ đơn."
        assert route_after_vietnamese(full_state) == "retrieve_node"

    def test_routes_to_retrieve_with_empty_state(self):
        assert route_after_vietnamese({"tutor_response": "some response"}) == "retrieve_node"
