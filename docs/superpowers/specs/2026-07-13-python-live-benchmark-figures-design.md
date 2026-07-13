# Python-rendered live benchmark figures

## Goal

Replace browser-generated research charts in the TRACE-CAG benchmark dashboard with figures rendered from validated benchmark summaries by Python. The dashboard remains live, but JavaScript only refreshes image artifacts and never calculates or draws research metrics.

## Architecture

Create a focused Python figure module beside the benchmark dashboard. It accepts the dashboard summary model as its only metric input and emits immutable figure artifacts plus a small manifest. Metric computation stays in the existing aggregation layer; the renderer only validates, formats, and plots supplied values.

Matplotlib and Seaborn are the default plotting stack. Graphviz may be used for static architecture or routing diagrams when available, with a Matplotlib fallback so the dashboard does not require an external executable.

For live runs, the dashboard server triggers a lightweight PNG render after five newly completed samples or after 30 seconds, whichever occurs first. Rendering is serialized and atomic: files are written to a temporary path and renamed only after a successful save. A failed render leaves the last valid image visible and reports the failure in dashboard status.

At stage completion, the renderer additionally emits SVG and PDF publication artifacts. PNG output uses 300 DPI. The browser displays PNG through ordinary `img` elements and refreshes URLs using the figure manifest version, avoiding stale browser caches.

## Figure set

The renderer covers the current research views:

- DriftBench route accuracy with Wilson 95% confidence intervals.
- Unsafe acceptance with Wilson 95% confidence intervals.
- Per-drift-type heatmap and breakdown.
- Route confusion matrix and patch recall.
- Exploratory threshold-sensitivity curves.
- Public-QA quality, latency, and token-cost comparisons.
- Quality-cost scatter and paired-delta forest plots.
- Benchmark progress/timeline charts.
- TRACE-CAG certificate and routing schematic.

Missing or incomplete metrics produce a clearly labelled `Pending scheduled evaluation` panel. The renderer must not substitute values, combine suites, or infer missing results.

## Research presentation standard

All plots use a shared publication style: serif typography, color-blind-safe palette, restrained grid lines, explicit units, visible sample size, and captions that identify the confidence interval method. Axis limits are metric-aware and never visually exaggerate small differences. No 3D effects are allowed.

Each render manifest records the figure ID, available formats, creation timestamp, source dataset hash, configuration hash, suite/sample count, metric name, confidence-interval method, and artifact checksum. This metadata makes dashboard figures traceable to benchmark inputs.

## Dashboard behavior

Research chart containers become image components sourced from Python artifacts. Existing KPI text, progress state, runner controls, and logs remain HTML and continue updating through the existing event stream. JavaScript may refresh an image, download an existing artifact, or show its metadata; it must not contain chart geometry or metric formulas.

While a new image is rendering, the previous valid image remains displayed with a small updating indicator. If no valid artifact exists, the dashboard shows an accessible pending/error state. SVG and PDF download actions appear only when those finalized formats exist.

## Validation and tests

Unit tests validate source-summary requirements, filenames, manifest metadata, pending panels, and atomic replacement. Figure tests use small deterministic fixtures and check that PNG, SVG, and PDF outputs are valid and non-empty. Contract tests ensure captions and displayed values match the input summary and that 24-, 122-, and 240-case suites cannot be mixed.

Dashboard tests verify that research charts use image endpoints, cache-busting versions change after a render, incomplete renders preserve the previous image, and no browser-side chart builder remains. A browser smoke test confirms figures load and update during a simulated live benchmark.

## Non-goals

This change does not alter benchmark metrics, thresholds, model calls, dataset scheduling, or the paper's claims. Interactive tooltips and client-side chart manipulation are intentionally excluded; traceability and publication reproducibility take priority.
