# Python-rendered Live Benchmark Figures Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace browser-built research charts with reproducible Matplotlib/Seaborn artifacts that update safely during benchmark runs and export publication-ready PNG/SVG/PDF files.

**Architecture:** Benchmark reporting emits validated `tracecag.figure-summary.v1` and runner logs emit `tracecag.progress-summary.v1`; the renderer consumes only these contracts. A serialized coordinator writes content-addressed figures and atomically publishes the manifest last. The dashboard serves only manifest-allowlisted artifacts and JavaScript swaps images on named SSE events without calculating metrics or geometry.

**Tech Stack:** Python 3.11+, Matplotlib `Agg`, Seaborn, standard-library HTTP/SSE, pytest, Playwright.

---

## Chunk 1: Reporting contracts

### Task 1: Emit schema-compliant research summaries

**Files:**
- Create: `ai-service/model-development/benchmark/tracecag_bench/reporting/figure_summary.py`
- Modify: `ai-service/model-development/benchmark/tracecag_bench/reporting/json_report.py`
- Modify: `ai-service/model-development/benchmark/tracecag_bench/protocols/drift_safety.py`
- Modify: `ai-service/model-development/benchmark/tracecag_bench/protocols/public_qa.py`
- Create: `ai-service/tests/trace_cag/test_figure_summary_contract.py`

- [ ] Write `test_rate_contract_preserves_zero_and_missing` and `test_bounded_mean_does_not_use_wilson`; run the focused file and expect import failure.
- [ ] Implement rate/bounded-mean constructors with explicit `availability`, nullable bounds, numerator/denominator only for binomial metrics, and canonical JSON hashing.
- [ ] Run the two tests and expect PASS; commit the focused files.
- [ ] Write failing tests for required `run_id`, `stage_id`, explicit `suite_id`, completed/target counts, normalized config with explicit nulls, dataset hash, and mixed-suite rejection.
- [ ] Extend report construction to publish `tracecag.figure-summary.v1`, copying computed metrics without recalculating them in the renderer; run tests and commit.
- [ ] Write provenance tests proving `dataset.source_dataset_hash = SHA256(canonical_json({dataset_id, revision, rows}))`, with rows normalized/sorted by stable ID, reordered input producing the same hash, changed row content producing a different hash, and paths/mtimes excluded. Test `configuration_hash` over the complete normalized config with explicit nulls.
- [ ] Compute both provenance hashes in aggregation, expose only the digests (never raw rows) to the renderer contract, validate lowercase SHA-256 form, run tests, and commit.
- [ ] Write failing registry-input tests for route confusion counts, patch recall, threshold series, per-drift unsafe acceptance, Public-QA EM/F1/R@5, P95 wall latency, per-sample tokens, and paired deltas.
- [ ] Populate those exact summary paths when source data exists; mark unavailable paths `pending` rather than zero; run tests and commit.
- [ ] Write failing tests for a validated periodic partial summary with `partial=true`, progress-matching completed/target counts, the same field schema as final output, and research figures pending when no valid partial exists.
- [ ] Emit partial summaries at the same five-observation/30-second boundaries when sufficient observations exist; reject count mismatch with progress. Test final publication uses `partial=false` and is the only completion signal; run tests and commit.

### Task 2: Emit and validate live progress observations

**Files:**
- Modify: `ai-service/model-development/benchmark/tracecag_bench/protocols/public_qa.py`
- Modify: `ai-service/model-development/benchmark/run_daily_benchmark.py`
- Create: `ai-service/model-development/benchmark/tracecag_bench/reporting/progress.py`
- Modify: `ai-service/tests/trace_cag/test_daily_benchmark_runner.py`
- Modify: `ai-service/tests/trace_cag/test_figure_summary_contract.py`

- [ ] Write failing tests for terminal markers containing `run_id`, `stage_id`, `suite_id`, stable `sample_id`, UTC `completed_at`, elapsed seconds, monotonic count, and target.
- [ ] Emit one JSON progress marker after each terminal sample observation and carry day/stage identities from the daily runner; run tests and commit.
- [ ] Write failing parser tests for duplicate IDs, nonterminal records, out-of-order timestamps/counts, over-target count, and mismatch with a later research partial summary.
- [ ] Implement `tracecag.progress-summary.v1` validation and reject invalid observations; run tests and commit.

## Chunk 2: Deterministic renderer

### Task 3: Add plotting stack and artifact publication

**Files:**
- Modify: `ai-service/requirements.txt`
- Create: `ai-service/model-development/scripts/benchmark_figures.py`
- Create: `ai-service/tests/trace_cag/test_benchmark_figures.py`

- [ ] Add `matplotlib>=3.8,<4`, `seaborn>=0.13,<0.14`, `playwright>=1.50,<2`, and `pytest-playwright>=0.7,<1`; install into `ai-service/venv`, run `venv/bin/python -m playwright install chromium`, and verify imports/browser launch before renderer tests.
- [ ] Write failing tests for canonical source/config hashes, explicit null normalization, order preservation, renderer/style/dimension/DPI/backend/format inputs, and 16-character lowercase artifact versions.
- [ ] Implement hashing with UTF-8 canonical JSON and `MPLBACKEND=Agg` before importing pyplot; run tests and commit.
- [ ] Write failing tests for per-format filename/checksum/media type/size, all manifest fields, stable `manifest_version` exclusions, exact-byte changes, and allowlist snapshot.
- [ ] Implement versioned files, close/fsync, atomic manifest replacement last, retain current+previous, and cleanup only after later successful publication; run tests and commit.
- [ ] Add failure tests for PNG/SVG/PDF writes and manifest publication; verify the prior manifest/artifacts remain; implement recovery and commit.

### Task 4: Render the exact approved figure registry

**Files:**
- Modify: `ai-service/model-development/scripts/benchmark_figures.py`
- Modify: `ai-service/tests/trace_cag/test_benchmark_figures.py`
- Create: `ai-service/model-development/benchmark/tracecag_bench/reporting/tracecag_routing.json`

- [ ] Parameterize tests over the 13 IDs: `drift_route_accuracy`, `drift_unsafe_acceptance`, `drift_type_heatmap`, `route_confusion_matrix`, `patch_recall`, `threshold_sensitivity`, `publicqa_quality`, `publicqa_latency`, `publicqa_tokens`, `quality_cost_scatter`, `paired_delta_forest`, `run_progress`, and `tracecag_routing`.
- [ ] Assert each exact JSON path, suite scope, pending rule, physical size, and axis policy from the approved spec; expect failures.
- [ ] Configure deterministic DejaVu Serif, color-blind palette, constrained layout without tight bbox, SVG/PDF font metadata, and fixed 300-DPI dimensions.
- [ ] Implement rate bars with supplied intervals, heatmap all-cells gate, count + row-normalized confusion panels, threshold panels, grouped Public-QA quality, stacked per-sample tokens, scatter, forest, progress, and static routing diagram.
- [ ] Implement routing with Matplotlib as the guaranteed deterministic renderer. If optional Graphviz is detected, require it to match the same node/edge specification; test a missing/failed Graphviz executable falls back to Matplotlib and still emits valid deterministic output.
- [ ] Structurally assert labels, units, `n`, CI method, point/error-bar counts, axis bounds, and exact PNG pixels for every registry size; run tests and commit.
- [ ] Verify partial eligibility; successful validated completion creates SVG/PDF, while pending/failed/cancelled runs create no finalized formats and invent no values; run tests and commit.

## Chunk 3: Live lifecycle and HTTP API

### Task 5: Add serialized rendering coordinator

**Files:**
- Create: `ai-service/model-development/scripts/benchmark_figure_coordinator.py`
- Create: `ai-service/tests/trace_cag/test_benchmark_figure_coordinator.py`
- Modify: `ai-service/model-development/scripts/benchmark_dashboard.py:816-1345`

- [ ] With a fake clock, write failing tests for four samples rendering at 30 seconds, five rendering immediately, no zero-delta render, timer reset, per-run/stage reset, and run switching.
- [ ] Implement per-`(run_id, stage_id)` counters and timers; run tests and commit.
- [ ] Write failing concurrency tests for global serialization, arrivals during render, exactly one coalesced follow-up, and timer cancellation.
- [ ] Implement a lock/condition-based coordinator safe under `ThreadingHTTPServer`; run tests and commit.
- [ ] Write failing lifecycle tests for validated-report completion, failed/cancelled last-PNG preservation, no final SVG/PDF, restart discovery, write failures, and cleanup after later success.
- [ ] Implement lifecycle handling and startup discovery; run tests and commit.

### Task 6: Serve manifest and artifacts safely

**Files:**
- Modify: `ai-service/model-development/scripts/benchmark_dashboard.py:1211-1345`
- Create: `ai-service/tests/trace_cag/test_benchmark_dashboard_figures.py`

- [ ] Write failing tests for `GET /api/figures` status/error/manifest contract and named `figures_changed` SSE event published only after successful manifest replacement.
- [ ] Implement endpoint and event; run focused tests and commit.
- [ ] Write failing tests for URL-decoded traversal, subpaths, unknown names, stale/unlisted artifacts, exact manifest filename, quoted checksum ETag, media type, size, and `Cache-Control: public, max-age=31536000, immutable`.
- [ ] Serve from an immutable in-memory manifest allowlist snapshot and return 404 for every rejected path; run tests and commit.
- [ ] Preserve CSV/Markdown/statistics export behavior and replace legacy handmade SVG export with renderer artifacts; run dashboard self-test and commit.

## Chunk 4: Image-only dashboard

### Task 7: Remove browser research-chart geometry

**Files:**
- Modify: `ai-service/model-development/scripts/benchmark_dashboard.py:1700-2550`
- Modify: `ai-service/tests/trace_cag/test_benchmark_dashboard_figures.py`
- Create: `ai-service/tests/browser/test_benchmark_dashboard_figures.py`

- [ ] Write failing source tests prohibiting `barChart`, `heatmapChart`, `scatterPlot`, `stackedTokenChart`, `forestPlot`, `stackedRouteChart`, `timeSeriesChart`, client SVG serialization, canvas PNG conversion, and research metric derivation.
- [ ] Implement one manifest-backed `<figure><img><figcaption>` component with intrinsic dimensions/aspect ratio, alt text, keyboard-accessible format links, and finalized SVG/PDF visibility only when present; run tests and commit.
- [ ] Write failing DOM tests for pending/error live regions, visible updating status while the old image remains, retry after load failure, and manifest change during image load.
- [ ] Fetch `/api/figures` initially and on named SSE events; preload then atomically swap `?v=<artifact_version>`, retaining the previous DOM image on failure; run tests and commit.
- [ ] Map Overview, DriftBench, Public QA, Statistics, Runner progress, and Paper views only to the 13 approved figure IDs. Keep logs as HTML and KPI values as presentation-only formatting of supplied Python fields.
- [ ] Add a pytest fixture that starts the dashboard on an ephemeral localhost port, waits for `/health`, yields `base_url`, and always terminates the process. Use pytest-playwright's Chromium `page` fixture.
- [ ] Run `cd ai-service && venv/bin/pytest tests/browser/test_benchmark_dashboard_figures.py --browser chromium -q`; expect all browser behaviors to pass.

### Task 8: Final verification and required reviews

**Files:** focused implementation and tests above only.

- [ ] Run `cd ai-service && venv/bin/pytest tests/trace_cag/test_figure_summary_contract.py tests/trace_cag/test_benchmark_figures.py tests/trace_cag/test_benchmark_figure_coordinator.py tests/trace_cag/test_benchmark_dashboard_figures.py tests/trace_cag/test_daily_benchmark_runner.py -q`.
- [ ] Run `cd ai-service && venv/bin/python model-development/scripts/benchmark_dashboard.py --self-test`.
- [ ] Run `cd ai-service && venv/bin/pytest model-development/tracecag_benchmark/tests -q` and the reporting/protocol tests.
- [ ] Export assets and verify manifest checksums plus PNG/SVG/PDF files under `model-development/reports/benchmark_dashboard_assets` without deleting CSV/Markdown outputs.
- [ ] Start the dashboard and run the Playwright smoke test against it; verify an image version changes after a simulated progress marker without page reload.
- [ ] Request the required test-writer review after implementation, security review for artifact endpoints/path handling, and final code review; address findings and rerun focused tests.
- [ ] Report exact test counts, artifact paths, dashboard URL, and every research panel still marked pending.
