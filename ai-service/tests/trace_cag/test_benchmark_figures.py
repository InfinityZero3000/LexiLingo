from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).parents[2] / "model-development" / "scripts" / "benchmark_figures.py"
SPEC = importlib.util.spec_from_file_location("benchmark_figures", MODULE_PATH)
assert SPEC and SPEC.loader
figures = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = figures
SPEC.loader.exec_module(figures)


EXPECTED = {
    "drift_route_accuracy": ("metrics.methods[].route_accuracy", "driftbench", (9.6, 5.8), "rate_0_1"),
    "drift_unsafe_acceptance": ("metrics.methods[].unsafe_acceptance", "driftbench", (7.2, 4.2), "rate_0_1"),
    "drift_type_heatmap": ("metrics.methods[].drift_types.<drift_type>.unsafe_acceptance", "driftbench", (8.0, 4.8), "rate_0_1"),
    "route_confusion_matrix": ("metrics.methods[].route_confusion.{labels,counts}", "driftbench", (7.2, 4.8), "count_and_row_normalized"),
    "patch_recall": ("metrics.methods[].patch_recall", "driftbench", (7.2, 3.8), "rate_0_1"),
    "threshold_sensitivity": ("metrics.thresholds[].{threshold,route_accuracy,unsafe_acceptance}", "sensitivity", (7.2, 4.8), "threshold_rate_panels"),
    "publicqa_quality": ("metrics.methods[].quality.{exact_match,f1,recall_at_5}", "publicqa", (7.2, 4.2), "rate_0_1"),
    "publicqa_latency": ("metrics.methods[].latency.p95_wall_clock_ms", "publicqa", (7.2, 4.2), "zero_to_105max"),
    "publicqa_tokens": ("metrics.methods[].tokens.{effective_prompt,saved_prompt,completion}_per_sample", "publicqa", (7.2, 4.2), "zero_to_105max"),
    "quality_cost_scatter": ("metrics.methods[].{quality.f1,tokens.effective_prompt_per_sample}", "publicqa", (7.2, 4.8), "zero_origin"),
    "paired_delta_forest": ("metrics.paired_deltas[]", "publicqa", (7.2, 4.8), "symmetric_zero"),
    "run_progress": ("observations[].{stage_id,elapsed_seconds,completed_count}", "any", (7.2, 3.8), "zero_to_105max"),
    "tracecag_routing": ("reporting/tracecag_routing.json", "static", (7.2, 4.8), "diagram"),
}


def summary() -> dict:
    rate = {"estimate": .75, "numerator": 3, "denominator": 4, "ci_low": .30, "ci_high": .95, "ci_method": "wilson_95", "availability": "ready"}
    bounded = {"estimate": .60, "n": 4, "ci_low": .50, "ci_high": .70, "ci_method": "paired_bootstrap_95", "availability": "ready"}
    scalar = lambda value, unit: {"value": value, "unit": unit, "availability": "ready"}
    config = {"model": "model", "provider": "groq", "generation_policy": "auto", "evidence_mode": "candidate_pool", "seed": 42, "cache_repeats": 2, "modes": ["b", "a"], "route_threshold": None, "patch_threshold": None}
    return {
        "schema_version": "tracecag.figure-summary.v1", "run_id": "run-1", "stage_id": "full",
        "suite_id": "driftbench_v2_smoke_24", "partial": False, "completed_count": 4, "target_count": 4,
        "dataset": {"id": "driftbench-v2", "revision": "v2", "source_dataset_hash": "a" * 64},
        "config": config, "configuration_hash": figures.configuration_hash(config),
        "availability": "ready",
        "metrics": {
            "methods": [{"method_id": "trace", "label": "TRACE-CAG", "route_accuracy": rate, "unsafe_acceptance": rate, "patch_recall": rate,
                "drift_types": {"policy": {"unsafe_acceptance": rate}},
                "route_confusion": {"labels": ["L0", "L2"], "counts": [[2, 0], [1, 1]]},
                "quality": {"exact_match": rate, "f1": bounded, "recall_at_5": bounded},
                "latency": {"p95_wall_clock_ms": scalar(120, "ms")},
                "tokens": {"effective_prompt_per_sample": scalar(100, "tokens/sample"), "saved_prompt_per_sample": scalar(20, "tokens/sample"), "completion_per_sample": scalar(30, "tokens/sample")}}],
            "thresholds": [{"threshold": .2, "route_accuracy": rate, "unsafe_acceptance": rate}, {"threshold": .8, "route_accuracy": rate, "unsafe_acceptance": rate}],
            "paired_deltas": [{"comparison_id": "trace-v-base", "label": "TRACE − baseline", "mean_delta": .1, "ci_low": -.1, "ci_high": .3, "ci_method": "paired_bootstrap_95", "n": 4, "availability": "ready"}],
        },
    }


@pytest.mark.parametrize("figure_id", sorted(EXPECTED))
def test_registry_is_exact(figure_id):
    spec = figures.FIGURE_REGISTRY[figure_id]
    assert (spec.input_path, spec.suite_scope, spec.size_inches, spec.axis_policy) == EXPECTED[figure_id]


def test_registry_has_only_approved_ids():
    assert set(figures.FIGURE_REGISTRY) == set(EXPECTED)


def test_canonical_hash_preserves_array_order_and_explicit_null():
    assert figures.canonical_json({"b": None, "a": [2, 1]}) == b'{"a":[2,1],"b":null}'
    assert figures.canonical_hash({"a": [1, 2]}) != figures.canonical_hash({"a": [2, 1]})
    assert figures.canonical_hash({"a": None}) != figures.canonical_hash({})


def test_configuration_hash_normalizes_missing_keys_to_null():
    normalized = figures.normalize_config({"model": "m", "ignored": "not-contract"})
    assert list(normalized) == list(figures.CONFIG_KEYS)
    assert normalized["route_threshold"] is None
    assert "ignored" not in normalized
    assert figures.configuration_hash({"model": "m"}) == figures.configuration_hash({"model": "m", "route_threshold": None})


def test_artifact_version_is_stable_16_lowercase_hex_and_tracks_inputs():
    value = summary()
    first = figures.artifact_version("drift_route_accuracy", value)
    assert len(first) == 16 and all(c in "0123456789abcdef" for c in first)
    assert first == figures.artifact_version("drift_route_accuracy", value)
    value["metrics"]["methods"][0]["route_accuracy"]["estimate"] = .5
    assert first != figures.artifact_version("drift_route_accuracy", value)


def test_artifact_version_tracks_renderer_dimensions_dpi_backend_formats(monkeypatch):
    value = summary(); baseline = figures.artifact_version("drift_route_accuracy", value, ("png",))
    assert baseline != figures.artifact_version("drift_route_accuracy", value, ("png", "svg"))
    monkeypatch.setattr(figures, "DPI", 144)
    assert baseline != figures.artifact_version("drift_route_accuracy", value, ("png",))


def test_invalid_supplied_source_hash_is_rejected():
    value = summary(); value["dataset"]["source_dataset_hash"] = "ABC"
    with pytest.raises(ValueError, match="lowercase SHA-256"):
        figures.artifact_version("drift_route_accuracy", value)


def test_routing_spec_has_stable_node_edge_contract():
    routing = json.loads(figures.routing_spec_path().read_text())
    assert routing["schema_version"] == "tracecag.routing-figure.v1"
    assert {n["id"] for n in routing["nodes"]} == {"request", "certificate", "hard_gate", "reuse", "patch", "rebuild"}
    assert all({"source", "target", "label"} <= set(edge) for edge in routing["edges"])


def test_manifest_version_excludes_timestamp_and_status():
    base = [{"figure_id": "x", "created_at": "first", "status": "ready", "artifact_version": "a", "artifacts": {}}]
    changed = [{**base[0], "created_at": "second", "status": "rendering"}]
    assert figures.canonical_hash(figures._manifest_stable(base)) == figures.canonical_hash(figures._manifest_stable(changed))


def test_load_manifest(tmp_path):
    assert figures.load_manifest(tmp_path) is None
    expected = {"schema_version": figures.SCHEMA_VERSION, "figures": []}
    (tmp_path / "manifest.json").write_text(json.dumps(expected))
    assert figures.manifest_for_root(tmp_path) == expected


@pytest.mark.skipif(importlib.util.find_spec("matplotlib") is None or importlib.util.find_spec("seaborn") is None, reason="plotting dependencies are not installed")
def test_publish_png_has_exact_pixels_checksum_and_manifest(tmp_path):
    from PIL import Image
    manifest = figures.publish_figures(summary(), tmp_path, figure_ids=["drift_route_accuracy"])
    entry = manifest["figures"][0]; artifact = entry["artifacts"]["png"]; path = tmp_path / artifact["filename"]
    assert entry["status"] == "ready" and path.exists()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == artifact["sha256"]
    assert artifact["byte_size"] == path.stat().st_size and artifact["media_type"] == "image/png"
    with Image.open(path) as image: assert image.size == (2880, 1740)
    assert figures.load_manifest(tmp_path)["manifest_version"] == manifest["manifest_version"]


@pytest.mark.skipif(importlib.util.find_spec("matplotlib") is None or importlib.util.find_spec("seaborn") is None, reason="plotting dependencies are not installed")
def test_finalized_formats_and_failed_publication_preserve_manifest(tmp_path, monkeypatch):
    previous = figures.publish_figures(summary(), tmp_path, finalized=True, figure_ids=["drift_route_accuracy"])
    entry = previous["figures"][0]
    assert set(entry["artifacts"]) == {"png", "svg", "pdf"}
    before = (tmp_path / "manifest.json").read_bytes()
    monkeypatch.setattr(figures, "_save_exact", lambda *args, **kwargs: (_ for _ in ()).throw(OSError("disk full")))
    with pytest.raises(OSError, match="disk full"):
        figures.publish_figures(summary(), tmp_path, figure_ids=["drift_route_accuracy"])
    assert (tmp_path / "manifest.json").read_bytes() == before


@pytest.mark.skipif(importlib.util.find_spec("matplotlib") is None or importlib.util.find_spec("seaborn") is None, reason="plotting dependencies are not installed")
@pytest.mark.parametrize("figure_id", sorted(EXPECTED))
def test_every_registry_figure_builds_with_approved_dimensions(figure_id):
    value = summary()
    if figure_id == "run_progress": value["observations"] = [{"sample_id":"1", "stage_id":"full", "elapsed_seconds":1, "completed_count":1}]
    fig = figures.build_figure(figure_id, value)
    try: assert tuple(fig.get_size_inches()) == pytest.approx(EXPECTED[figure_id][2])
    finally:
        import matplotlib.pyplot as plt
        plt.close(fig)
