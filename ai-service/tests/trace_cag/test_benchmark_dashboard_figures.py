from __future__ import annotations

import importlib.util
import re
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


def _compact_html() -> str:
    """Normalize whitespace without coupling layout tests to formatting."""
    return re.sub(r"\s+", " ", dashboard.HTML)


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


def test_primary_research_figures_span_the_full_figure_grid():
    html = _compact_html()

    assert ".figure-card--primary { grid-column: 1 / -1; }" in html
    assert 'new Set(["drift_route_accuracy", "drift_unsafe_acceptance", "route_confusion_matrix", "threshold_sensitivity"])' in html
    assert 'primaryIds.has(id) ? "figure-card--primary" : "figure-card--secondary"' in html


def test_figure_grid_aligns_cards_to_the_start_instead_of_stretching_them():
    html = _compact_html()

    assert ".figure-grid { align-items: start; }" in html
    assert ".figure-grid > .figure:only-child { grid-column: 1 / -1; }" in html
    assert ".figure { overflow: hidden; margin: 0 0 var(--spacing-4); min-width: 0; align-self: start; }" in html
    assert 'role="group" aria-label="Download ${esc(title)} figure"' in dashboard.HTML
    assert "a.button { min-height: 44px; padding-inline: var(--spacing-3); }" in html
    stats_pair = '${pythonFigure("threshold_sensitivity", "Exploratory threshold sensitivity")} ${pythonFigure("paired_delta_forest", "Paired deltas with supplied 95% CI")}'
    assert stats_pair in html


def test_figure_chrome_uses_compact_tokenized_padding():
    html = _compact_html()

    assert "padding: var(--spacing-3) var(--spacing-4);" in html
    assert ".figure-body { padding: var(--spacing-2); overflow-x: auto; }" in html
    assert "figcaption { padding: var(--spacing-1) var(--spacing-4) var(--spacing-3);" in html


def test_active_dashboard_section_is_centered_and_capped_at_1440_pixels():
    html = _compact_html()

    assert ".section { display: none; width: min(100%, 1440px); margin-inline: auto; }" in html


def test_responsive_breakpoints_collapse_figure_grids_to_one_column():
    html = _compact_html()

    assert "@media (max-width: 1180px)" in html
    assert ".grid2, .figure-grid { grid-template-columns: 1fr; }" in html
    assert "@media (max-width: 760px)" in html
    assert ".content { padding: var(--spacing-3); }" in html
    assert ".figure-body { padding: var(--spacing-1); }" in html


def test_python_figure_images_expose_intrinsic_dimensions_and_alt_text():
    html = _compact_html()

    assert "const width = Math.round(Number(entry.width_inches || 7.2) * Number(entry.dpi || 300));" in html
    assert "const height = Math.round(Number(entry.height_inches || 4.2) * Number(entry.dpi || 300));" in html
    assert '<img src="/figures/${esc(png.filename)}?v=${esc(entry.artifact_version)}" width="${width}" height="${height}" alt="${esc(entry.alt_text)}" loading="lazy">' in html
