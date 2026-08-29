from tracecag_bench.metrics.retrieval import retrieval_metrics
from tracecag_bench.metrics.safety import calibrate_thresholds, safety_metrics
from tracecag_bench.metrics.text import exact_match, token_f1
from tracecag_bench.schemas import RunObservation
from api.services.trace_cag.benchmark.ranking import _benchmark_evidence_snippet


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


def test_benchmark_evidence_snippet_keeps_definition_and_question_match():
    text = (
        "Avery Stone is a Canadian film director. "
        "This paragraph only describes unrelated awards. "
        "Avery Stone directed Moon Harbor in 1999. "
        "Another unrelated sentence mentions a festival."
    )

    snippet = _benchmark_evidence_snippet(
        question="Who directed Moon Harbor?",
        title="Avery Stone",
        text=text,
        max_sentences=2,
        max_chars=180,
    )

    assert "Avery Stone is a Canadian film director" in snippet
    assert "directed Moon Harbor" in snippet
    assert "unrelated awards" not in snippet


def test_all_support_distinguishes_half_retrieved_multihop_from_fully_retrieved():
    """recall@k averages over hops, so a 2-hop question with only one hop
    retrieved scores 0.5 — indistinguishable from genuine partial progress even
    though the question is unanswerable. all_support_at_k is the gate that
    separates them."""
    trace = [
        {"title": "Hop One", "text": "first supporting passage"},
        {"title": "Distractor", "text": "irrelevant"},
        {"title": "Hop Two", "text": "second supporting passage"},
    ]
    supporting = ("Hop One", "Hop Two")

    half = retrieval_metrics(trace[:2], supporting)
    assert half["recall_at_5"] == 0.5
    assert half["hit_at_5"] == 1.0
    assert half["all_support_at_5"] == 0.0

    full = retrieval_metrics(trace, supporting)
    assert full["recall_at_5"] == 1.0
    assert full["all_support_at_5"] == 1.0


def test_answer_in_context_tracks_reader_ceiling_not_title_overlap():
    trace = [{"title": "Hop One", "text": "The arena seats 3,677 people."}]
    reachable = retrieval_metrics(trace, ("Hop One",), gold_answers=("3,677",))
    assert reachable["answer_in_context_at_5"] == 1.0

    # Right passage retrieved, but the gold string is not in it: the reader
    # cannot win this one, and EM=0 here is not a reader defect.
    unreachable = retrieval_metrics(trace, ("Hop One",), gold_answers=("9,984",))
    assert unreachable["recall_at_5"] == 1.0
    assert unreachable["answer_in_context_at_5"] == 0.0


def test_map_rewards_ranking_supporting_passages_higher():
    supporting = ("A", "B")
    top = [{"title": "A"}, {"title": "B"}, {"title": "X"}]
    bottom = [{"title": "X"}, {"title": "A"}, {"title": "B"}]

    assert retrieval_metrics(top, supporting)["recall_at_5"] == retrieval_metrics(bottom, supporting)["recall_at_5"]
    assert retrieval_metrics(top, supporting)["map_at_5"] > retrieval_metrics(bottom, supporting)["map_at_5"]


