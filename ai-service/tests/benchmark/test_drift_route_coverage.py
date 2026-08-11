from tracecag_bench.metrics.safety import safety_metrics, wilson_interval
from tracecag_bench.protocols.drift_safety import route_coverage_gate
from tracecag_bench.schemas import RunObservation


def _observation(
    sample_id, *, decision, layer, expected, safety="safe", reasons=(), error=""
):
    return RunObservation(
        sample_id=sample_id,
        mode="tracecag_full",
        cache_decision=decision,
        cache_layer=layer,
        expected_route=expected,
        safety_label=safety,
        error=error,
        cache_gate_meta={"reasons": list(reasons)},
    )


def test_route_coverage_gate_requires_all_safety_paths():
    observations = [
        _observation("reuse", decision="reuse", layer="L1", expected="L1_reuse"),
        _observation("patch", decision="patch", layer="L1", expected="L1_patch"),
        _observation("reject", decision="full", layer="none", expected="L2", safety="unsafe"),
        _observation(
            "race", decision="full", layer="none", expected="L2", safety="unsafe",
            reasons=("snapshot_changed_before_serve:learner:u1:profile",),
        ),
    ]

    gate = route_coverage_gate(observations)

    assert gate == {
        "passed": True,
        "checks": {
            "l1_reuse": True,
            "l1_patch": True,
            "unsafe_rejection": True,
            "optimistic_recheck": True,
        },
        "missing": [],
    }


def test_route_coverage_gate_reports_missing_paths():
    gate = route_coverage_gate([
        _observation("reject", decision="full", layer="none", expected="L2", safety="unsafe"),
    ])
    assert gate["passed"] is False
    assert gate["missing"] == ["l1_reuse", "l1_patch", "optimistic_recheck"]


def test_safety_metrics_count_failures_conservatively():
    metrics = safety_metrics([
        _observation("safe-patch", decision="patch", layer="L1", expected="L1_patch"),
        _observation("unsafe-error", decision="full", layer="none", expected="L2", safety="unsafe", error="timeout"),
    ])
    assert metrics["patch_precision"] == 1.0
    assert metrics["unsafe_serving_rate"] == 1.0
    assert metrics["availability"] == 0.5


def test_wilson_interval_is_bounded_and_contains_estimate():
    low, high = wilson_interval(8, 10)
    assert 0.0 <= low <= 0.8 <= high <= 1.0
