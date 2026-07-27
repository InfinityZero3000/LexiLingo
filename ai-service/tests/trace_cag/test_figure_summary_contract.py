from __future__ import annotations

import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).parents[2] / "model-development" / "benchmark"))

from tracecag_bench.reporting.figure_summary import (
    FigureSummaryError,
    bounded_mean,
    build_figure_summary,
    configuration_hash,
    normalize_config,
    rate,
    reject_mixed_suites,
    source_dataset_hash,
    validate_figure_summary,
)
from tracecag_bench.reporting.progress import (
    ProgressError,
    marker_line,
    parse_progress,
    terminal_marker,
)


def test_rate_contract_preserves_zero_and_missing():
    zero = rate(numerator=0, denominator=24, ci_low=0.0, ci_high=0.14)
    missing = rate(availability="pending", ci_method=None)
    assert zero["estimate"] == 0.0
    assert zero["numerator"] == 0
    assert missing["estimate"] is None
    assert missing["denominator"] is None


def test_bounded_mean_does_not_use_wilson():
    with pytest.raises(FigureSummaryError, match="Wilson"):
        bounded_mean(estimate=0.5, n=10, ci_method="wilson_95")
    item = bounded_mean(estimate=0.5, n=10)
    assert "numerator" not in item and item["ci_method"] is None


def test_provenance_hash_is_order_independent_and_excludes_paths():
    rows = [{"sample_id": "b", "value": 2, "path": "/tmp/a"}, {"sample_id": "a", "value": 1, "mtime": 7}]
    expected = source_dataset_hash("demo", "v1", rows)
    assert source_dataset_hash("demo", "v1", list(reversed(rows))) == expected
    assert source_dataset_hash("demo", "v1", [{"sample_id": "a", "value": 1}, {"sample_id": "b", "value": 2}]) == expected
    assert source_dataset_hash("demo", "v1", [{"sample_id": "a", "value": 9}]) != expected


def test_config_normalizes_explicit_nulls_and_preserves_mode_order():
    normalized = normalize_config({"model": "m", "modes": ("b", "a")})
    assert normalized["modes"] == ["b", "a"]
    assert normalized["route_threshold"] is None
    assert configuration_hash(normalized) == configuration_hash(dict(reversed(list(normalized.items()))))


def test_summary_requires_identity_counts_and_rejects_mixed_suites(tmp_path):
    dataset = tmp_path / "rows.jsonl"
    dataset.write_text('{"sample_id":"one","value":1}\n')
    summary = build_figure_summary(
        result={"observations": [{}], "figure_metrics": {}}, config={},
        dataset_path=dataset, dataset_id="demo", run_id="run", stage_id="full",
        suite_id="suite-a", completed_count=1, target_count=2, partial=True,
    )
    assert summary["partial"] is True and summary["completed_count"] == 1
    assert summary["configuration_hash"] == configuration_hash(summary["config"])
    with pytest.raises(FigureSummaryError, match="mixed suites"):
        reject_mixed_suites([summary, {**summary, "suite_id": "suite-b"}])


def test_progress_markers_validate_terminal_unique_monotonic_observations():
    first = terminal_marker(
        run_id="run", stage_id="full", suite_id="suite", sample_id="a",
        completed_count=1, target_count=2, elapsed_seconds=1,
        completed_at="2026-07-13T12:00:00Z",
    )
    second = terminal_marker(
        run_id="run", stage_id="full", suite_id="suite", sample_id="b",
        completed_count=2, target_count=2, elapsed_seconds=2,
        completed_at="2026-07-13T12:00:01Z",
    )
    progress = parse_progress([marker_line(first), "ordinary log", marker_line(second)])
    assert progress["schema_version"] == "tracecag.progress-summary.v1"
    assert len(progress["observations"]) == 2
    with pytest.raises(ProgressError, match="duplicate"):
        parse_progress([marker_line(first), marker_line({**second, "sample_id": "a"})])
    with pytest.raises(ProgressError, match="contiguous"):
        parse_progress([marker_line({**first, "completed_count": 2})])


def test_partial_summary_must_match_progress(tmp_path):
    dataset = tmp_path / "rows.json"
    dataset.write_text(json.dumps([{"id": "one"}]))
    summary = build_figure_summary(
        result={"figure_metrics": {}}, config={}, dataset_path=dataset,
        dataset_id="demo", run_id="run", stage_id="full", suite_id="suite",
        partial=True, completed_count=1, target_count=2,
    )
    progress = parse_progress([marker_line(terminal_marker(
        run_id="run", stage_id="full", suite_id="suite", sample_id="one",
        completed_count=1, target_count=2, elapsed_seconds=1,
        completed_at="2026-07-13T12:00:00Z",
    ))])
    validate_figure_summary(summary, progress=progress)
    with pytest.raises(FigureSummaryError, match="completed_count"):
        validate_figure_summary({**summary, "completed_count": 0}, progress=progress)
