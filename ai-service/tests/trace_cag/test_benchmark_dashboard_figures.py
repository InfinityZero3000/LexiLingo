from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


SCRIPTS = Path(__file__).parents[2] / "model-development" / "scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    "benchmark_dashboard_for_figure_tests", SCRIPTS / "benchmark_dashboard.py"
)
assert SPEC and SPEC.loader
dashboard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = dashboard
SPEC.loader.exec_module(dashboard)


def _dashboard_summary(*, n_safe: int = 1) -> dict:
    return {
        "driftbench": {
            "methods": [{
                "id": "cert_v2_full",
                "label": "TRACE-CAG certificate",
                "metrics": {
                    "n_total": 4,
                    "n_safe": n_safe,
                    "n_unsafe": 3,
                    "route_accuracy": 0.75,
                    "unsafe_acceptance_rate": 0.0,
                    "patch_rate": 0.0,
                    "ci95": {},
                    "by_drift_type": {},
                },
            }],
        },
        "publicqa": {"runs": []},
        "logs": {"latest": None},
    }


def test_dashboard_adapter_marks_patch_recall_pending_without_patchable_cases():
    payloads = dashboard._dashboard_figure_summaries(_dashboard_summary(n_safe=0))
    drift_payload = next(payload for scope, payload, _, _ in payloads if scope == "drift")
    patch = drift_payload["metrics"]["methods"][0]["patch_recall"]

    assert patch["denominator"] == 0
    assert patch["availability"] == "pending"


def test_dashboard_figure_manifest_caches_identical_source_signature(tmp_path, monkeypatch):
    summary = _dashboard_summary()
    monkeypatch.setattr(dashboard, "build_summary", lambda root: summary)
    dashboard.FIGURE_CACHE.update(signature=None, manifest=None)
    calls = []

    def publish(payload, output, *, finalized, figure_ids):
        calls.append((output, tuple(figure_ids)))
        figure_id = figure_ids[0]
        return {
            "manifest_version": f"version-{len(calls)}",
            "figures": [{
                "figure_id": figure_id,
                "artifact_version": "abc",
                "artifacts": {
                    "png": {
                        "filename": f"{figure_id}.abc.png",
                        "media_type": "image/png",
                        "sha256": "a" * 64,
                    },
                },
            }],
        }

    monkeypatch.setattr(dashboard, "publish_figures", publish)
    first = dashboard.dashboard_figure_manifest(tmp_path)
    second = dashboard.dashboard_figure_manifest(tmp_path)

    assert second is first
    assert len(calls) == 2  # drift and live scopes, rendered only on first request
    assert {f["artifacts"]["png"]["filename"] for f in first["figures"]} == {
        "drift/drift_route_accuracy.abc.png",
        "live/run_progress.abc.png",
    }


def test_manifest_signature_changes_when_benchmark_metrics_change(tmp_path, monkeypatch):
    summary = _dashboard_summary()
    monkeypatch.setattr(dashboard, "build_summary", lambda root: summary)
    dashboard.FIGURE_CACHE.update(signature=None, manifest=None)
    calls = []

    def publish(payload, output, *, finalized, figure_ids):
        calls.append(payload["completed_count"])
        return {"manifest_version": str(len(calls)), "figures": []}

    monkeypatch.setattr(dashboard, "publish_figures", publish)
    first = dashboard.dashboard_figure_manifest(tmp_path)
    summary["driftbench"]["methods"][0]["metrics"]["route_accuracy"] = 0.5
    second = dashboard.dashboard_figure_manifest(tmp_path)

    assert first["manifest_version"] != second["manifest_version"]
    assert len(calls) == 4
