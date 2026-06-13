from tracecag_bench.metrics.retrieval import retrieval_metrics
from tracecag_bench.metrics.safety import calibrate_thresholds, safety_metrics
from tracecag_bench.metrics.text import exact_match, token_f1
from tracecag_bench.schemas import RunObservation


def test_text_metrics_use_answer_aliases_and_token_multiplicity():
    assert exact_match("The Chief of Protocol.", ("chief of protocol",)) == 1.0
    assert token_f1("red red car", ("red car",)) == 0.8


def test_retrieval_metrics_use_ranked_trace_not_answer_quality():
    trace = [
        {"title": "distractor", "is_relevant": False},
        {"title": "Scott Derrickson", "is_relevant": True},
        {"title": "Ed Wood", "is_relevant": True},
    ]
    result = retrieval_metrics(trace, ("Scott Derrickson", "Ed Wood"))
    assert result["recall_at_1"] == 0.0
    assert result["recall_at_3"] == 1.0
    assert result["mrr_at_5"] == 0.5


def test_safety_metrics_exclude_uncertain_and_map_l0_route():
    observations = [
        RunObservation("safe", "trace", cache_hit=True, cache_decision="reuse", cache_layer="L0", expected_route="L0", safety_label="safe"),
        RunObservation("unsafe", "trace", cache_hit=False, cache_decision="full", cache_layer="none", expected_route="L2", safety_label="unsafe"),
        RunObservation("uncertain", "trace", cache_hit=True, cache_decision="reuse", cache_layer="L0", expected_route="L0", safety_label="uncertain"),
    ]
    result = safety_metrics(observations)
    assert result["safe_reuse_precision"] == 1.0
    assert result["unsafe_acceptance_rate"] == 0.0
    assert result["route_accuracy"] == 1.0
    assert result["uncertain_count"] == 1.0


def test_calibration_respects_unsafe_budget():
    observations = [
        RunObservation("safe", "trace", cache_gate_meta={"risk": 0.20}, safety_label="safe"),
        RunObservation("unsafe", "trace", cache_gate_meta={"risk": 0.30}, safety_label="unsafe"),
    ]
    result = calibrate_thresholds(observations, epsilon=0.0, grid=(0.1, 0.2, 0.3))
    assert result["tau_patch"] == 0.2
    assert result["admissible_recall"] == 1.0
    assert result["unsafe_acceptance_rate"] == 0.0
