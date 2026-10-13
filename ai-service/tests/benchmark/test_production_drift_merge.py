import hashlib
import json
from pathlib import Path

import pytest

from aggregate_drift import aggregate, latex_table
from tracecag_bench import cli
from tracecag_bench.config import BenchmarkConfig
from tracecag_bench.datasets.driftbench import load_driftbench
from tracecag_bench.reporting.json_report import validate_run


DATASET = (
    Path(__file__).resolve().parents[2]
    / "model-development/datasets/benchmarks/trace_driftbench_v2_240/test.jsonl"
)


def test_production_v2_240_dataset_keeps_cluster_and_review_provenance():
    rows = [json.loads(line) for line in DATASET.read_text(encoding="utf-8").splitlines()]
    clusters = load_driftbench(DATASET)

    assert len(rows) == len(clusters) == 12
    assert sum(len(cluster.variants) for cluster in clusters) == 96
    assert len({cluster.cluster_id for cluster in clusters}) == 12
    assert all(cluster.base.drift_type == "base" for cluster in clusters)
    assert all(row["provenance"]["reviewer_status"] == "pending" for row in rows)
    assert all(row["provenance"]["source_hash"] for row in rows)
    assert all(row["provenance"]["generator"] == "build_driftbench_v2_240.py" for row in rows)


def test_drift_cli_parses_explicit_dataset_path():
    args = cli.build_parser().parse_args(
        ["drift-safety", "--split", "test", "--dataset-path", str(DATASET), "--n-clusters", "2"]
    )

    assert args.dataset_path == DATASET
    assert args.n_clusters == 2


def test_strict_drift_run_fails_validation_with_unwritable_kg(monkeypatch):
    monkeypatch.setenv("TRACECAG_KG_STRICT_SNAPSHOT", "true")
    report = {"protocol": "drift_safety", "mode": "tracecag_cached", "observations": [],
              "kg_preflight": {"status": "not_writable"},
              "route_coverage_gate": {"passed": False, "missing": ["l1_reuse", "l1_patch"]}}
    result = validate_run(report, BenchmarkConfig(require_primary_provider=False))
    assert result["passed"] is False
    assert "not_writable" in result["violations"][0]


@pytest.mark.asyncio
async def test_drift_cli_reports_selected_dataset_and_review_status(monkeypatch, tmp_path):
    report_path = tmp_path / "drift.json"
    args = cli.build_parser().parse_args(
        ["drift-safety", "--dataset-path", str(DATASET), "--n-clusters", "2",
         "--generation-policy", "extractive", "--report-json", str(report_path)]
    )
    monkeypatch.setattr(
        cli, "_config_from_args",
        lambda _: BenchmarkConfig(generation_policy="extractive", require_primary_provider=False),
    )

    async def fake_protocol(clusters, mode, config, *, split):
        assert len(clusters) == 2
        assert split == "test"
        assert mode.name == args.mode
        return {"protocol": "drift_safety", "mode": mode.name, "observations": []}

    monkeypatch.setattr(cli, "run_drift_safety_protocol", fake_protocol)

    assert await cli.run_args(args) == 0
    report = json.loads(report_path.read_text(encoding="utf-8"))
    assert report["dataset"]["path"] == str(DATASET)
    assert report["dataset"]["sha256"] == hashlib.sha256(DATASET.read_bytes()).hexdigest()
    assert report["dataset_review_status"] == "pending"
    assert report["exploratory"] is True
    assert report["run_validation"]["passed"] is True


def _write_report(tmp_path, mode, **changes):
    report = {
        "protocol": "drift_safety",
        "dataset": {"sha256": "dataset-sha"},
        "configuration": {"provider": "groq", "model": "test-model",
                          "generation_policy": "llm", "implementation_sha256": "implementation-sha"},
        "kg_preflight": {"source_sha256": "kg-sha"},
        "dataset_review_status": "pending",
        "run_validation": {"passed": True},
        "mode": mode,
        "observations": [
            {"safety_label": "safe", "cache_decision": "reuse", "cache_layer": "L0", "expected_route": "L0"},
            {"safety_label": "safe", "cache_decision": "patch", "cache_layer": "L1", "expected_route": "L1_patch"},
            {"safety_label": "unsafe", "cache_decision": "full", "cache_layer": "none", "expected_route": "L2"},
            {"safety_label": "unsafe", "cache_decision": "reuse", "cache_layer": "L1", "expected_route": "L2"},
        ],
        "summary": {
            "safe_reuse_precision": 2 / 3,
            "admissible_recall": 1.0,
            "unsafe_acceptance_rate": 0.5,
            "fallback_rate": 0.25,
            "patch_recall": 1.0,
            "route_accuracy": 0.75,
            "latency": {"mean_ms": 12.5},
        },
    }
    report.update(changes)
    path = tmp_path / f"{mode}.json"
    path.write_text(json.dumps(report), encoding="utf-8")
    return path


def test_aggregate_exports_valid_metrics_intervals_and_latex(tmp_path):
    paths = [_write_report(tmp_path, "tracecag"), _write_report(tmp_path, "l2_only")]

    result = aggregate(paths)

    assert result["dataset_sha256"] == "dataset-sha"
    assert result["dataset_review_status"] == "pending"
    assert result["exploratory"] is True
    assert result["latency_type"] == "measured_end_to_end"
    assert [item["mode"] for item in result["methods"]] == ["tracecag", "l2_only"]
    method = result["methods"][0]
    assert method["n"] == 4
    assert method["safe_reuse_precision"] == pytest.approx(2 / 3)
    assert method["unsafe_acceptance_rate"] == 0.5
    assert method["route_accuracy"] == 0.75
    assert method["mean_latency_ms"] == 12.5
    assert method["unsafe_acceptance_ci_95"] == pytest.approx((0.094531, 0.905469), abs=1e-5)
    assert method["route_accuracy_ci_95"] == pytest.approx((0.300642, 0.954413), abs=1e-5)
    table = latex_table(result)
    assert r"\begin{tabular}" in table
    assert r"tracecag & 66.7 & 100.0 & 50.0 & 25.0 & 100.0 & 75.0 & 12.5 \\" in table
    assert r"l2\_only" in table
    assert r"\end{tabular}" in table


@pytest.mark.parametrize(
    "change",
    [
        {"run_validation": {"passed": False}},
        {"run_validation": {}},
        {"dataset": {"sha256": "other-sha"}},
        {"configuration": {"provider": "other", "model": "test-model"}},
        {"configuration": {"provider": "groq", "model": "other-model"}},
        {"configuration": {"provider": "groq", "model": "test-model", "generation_policy": "extractive"}},
        {"configuration": {"provider": "groq", "model": "test-model", "implementation_sha256": "other-sha"}},
        {"kg_preflight": {"source_sha256": "other-kg"}},
        {"dataset_review_status": "approved"},
        {"protocol": "legacy_simulator"},
        {"observations": [{"error": "provider failed"}]},
        {"observations": []},
    ],
)
def test_aggregate_rejects_failed_incompatible_or_errored_report(tmp_path, change):
    valid = _write_report(tmp_path, "tracecag")
    invalid = _write_report(tmp_path, "l2_only", **change)

    with pytest.raises(ValueError):
        aggregate([valid, invalid])


def test_aggregate_rejects_duplicate_methods_and_empty_input(tmp_path):
    valid = _write_report(tmp_path, "tracecag")

    with pytest.raises(ValueError, match="duplicate method"):
        aggregate([valid, valid])
    with pytest.raises(ValueError, match="no reports"):
        aggregate([])
