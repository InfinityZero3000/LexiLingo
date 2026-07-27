# Python-rendered live benchmark figures

## Goal

Replace browser-generated research charts in the TRACE-CAG benchmark dashboard with figures rendered from validated benchmark summaries by Python. The dashboard remains live, but JavaScript only refreshes image artifacts and never calculates or draws research metrics.

## Architecture

Create a focused Python figure module beside the benchmark dashboard. It accepts a versioned figure-summary contract as its only metric input and emits content-addressed figure artifacts plus a manifest. Metric computation stays in the aggregation layer. For rates, that layer supplies the point estimate, numerator, denominator, nullable Wilson bounds, and an explicit availability state; the renderer verifies and plots those values but never calculates metrics or confidence intervals.

Matplotlib and Seaborn are the default plotting stack. Graphviz may be used for static architecture or routing diagrams when available, with a Matplotlib fallback so the dashboard does not require an external executable.

For each `(run_id, stage_id)`, a completed sample is a sample recorded by the runner with its terminal observation set and included in a validated partial summary. Render when `completed_count - last_rendered_count >= 5`, or when that delta is positive and 30 seconds have elapsed since the first unrendered completion. The first four samples therefore render after at most 30 seconds. Arrivals during rendering are coalesced into one subsequent render. Rendering is serialized globally and never concurrent.

With the current runner, only progress and timeline inputs are available before a report is aggregated. Those figures may update live immediately. Research figures update live only after the aggregation layer is extended to publish a validated partial summary containing the same fields as a final summary; otherwise their status remains `pending` and they update when the validated report appears. A partial summary carries explicit `run_id`, `stage_id`, `suite_id`, completed/target counts, and `partial=true`.

Successful validated report publication is the authoritative stage-completion signal. Only then does the renderer emit SVG and PDF publication artifacts. Failed or cancelled stages retain their last live PNG and never receive finalized formats. At startup, the server discovers validated completed reports and renders missing final artifacts. PNG output uses 300 DPI. The browser displays PNG through ordinary `img` elements and refreshes URLs using each figure's artifact version.

Artifacts use `<figure_id>.<artifact_version>.<format>`, where `artifact_version` is the first 16 hexadecimal characters of the SHA-256 digest of the figure input and renderer configuration. Each file is fully closed before a versioned manifest is atomically published last. A failure preserves the previous manifest and files. Superseded artifacts are retained for the current and previous manifest and cleaned on a later successful publication.

## Figure registry

The registry is code-owned and stable. Every entry declares its JSON inputs, suite scope, dimensions, eligibility, and pending rule.

| Figure ID | Input and axes | Size | Eligibility |
|---|---|---:|---|
| `drift_route_accuracy` | methods: route-accuracy estimate and Wilson bounds; x=accuracy %, y=method | 7.2 x 4.2 in | partial or final DriftBench suite |
| `drift_unsafe_acceptance` | methods: unsafe-acceptance estimate and Wilson bounds; x=rate %, y=method | 7.2 x 4.2 in | partial or final DriftBench suite |
| `drift_type_heatmap` | method x drift type; cell=unsafe-acceptance % | 8.0 x 4.8 in | final, or validated partial with all requested cells |
| `route_confusion_matrix` | rows=expected route, columns=actual route; cells=count, with a separately labelled row-normalized panel | 7.2 x 4.8 in | final DriftBench only |
| `patch_recall` | eligible patch cases: true positives/eligible cases, estimate and Wilson bounds; x=recall %, y=method | 7.2 x 3.8 in | final DriftBench only |
| `threshold_sensitivity` | supplied threshold series; x=threshold, y=route accuracy/unsafe acceptance; separate panels | 7.2 x 4.8 in | final sensitivity suite only |
| `publicqa_quality` | x=F1/EM/R@5 %, grouped by method | 7.2 x 4.2 in | partial or final single Public-QA suite |
| `publicqa_latency` | x=P95 wall-clock latency in ms, y=method | 7.2 x 4.2 in | final only; simulated cost excluded |
| `publicqa_tokens` | effective prompt, saved prompt, completion tokens per sample; stacked x, y=method | 7.2 x 4.2 in | final only |
| `quality_cost_scatter` | x=effective tokens/sample, y=F1 %, point=method | 7.2 x 4.8 in | final only |
| `paired_delta_forest` | supplied paired mean delta and 95% CI; x=delta, y=comparison | 7.2 x 4.8 in | final only |
| `run_progress` | x=elapsed wall time, y=completed sample count, line=stage | 7.2 x 3.8 in | live and final |
| `tracecag_routing` | version-controlled routing/certificate node-edge specification | 7.2 x 4.8 in | static |

Rate axes are fixed to `[0, 1]` and formatted as percentages. Confusion-matrix color limits are `[0, max(cell_count)]`; its normalized panel is `[0, 1]`. Threshold x limits use the supplied tested minimum/maximum and rate y limits remain `[0, 1]`. Latency, token, progress, and elapsed-time axes start at zero and end at `1.05 * max`, falling back to `[0, 1]` when all values are zero. Forest limits are symmetric about zero at `1.10 * max(abs(ci_low), abs(ci_high))`, with a fallback of `[-1, 1]`.

## Figure-summary contracts

The aggregation boundary emits schema `tracecag.figure-summary.v1`. Required identity and provenance fields are:

```json
{
  "schema_version": "tracecag.figure-summary.v1",
  "run_id": "day-01-20260713T120000Z",
  "stage_id": "full",
  "suite_id": "driftbench_v2_smoke_24",
  "partial": false,
  "completed_count": 24,
  "target_count": 24,
  "dataset": {"id": "driftbench-v2", "revision": "v2", "source_dataset_hash": "..."},
  "config": {
    "model": "qwen/qwen3-32b", "provider": "groq", "generation_policy": "auto",
    "evidence_mode": "candidate_pool", "seed": 42, "cache_repeats": 2,
    "modes": ["trace_cag"], "route_threshold": null, "patch_threshold": null
  },
  "availability": "ready",
  "metrics": {}
}
```

All listed fields are required. Unknown/absent optional configuration values normalize to JSON `null`; arrays preserve semantically significant order; numbers use JSON numeric values, not formatted strings. `availability` is `pending`, `ready`, or `invalid` and includes `error` when invalid.

Reusable metric objects have these exact shapes:

```json
{
  "rate": {"estimate": 0.875, "numerator": 21, "denominator": 24, "ci_low": 0.69, "ci_high": 0.96, "ci_method": "wilson_95", "availability": "ready"},
  "bounded_mean": {"estimate": 0.62, "n": 64, "ci_low": 0.57, "ci_high": 0.67, "ci_method": "paired_bootstrap_95", "availability": "ready"},
  "scalar": {"value": 1250.4, "unit": "ms", "availability": "ready"},
  "paired_delta": {"label": "TRACE-CAG - baseline", "mean": 0.12, "ci_low": 0.03, "ci_high": 0.21, "n": 24, "p_value": 0.01, "availability": "ready"}
}
```

Nullable numeric fields use `null`, never zero, for missing values. The exact registry paths are:

- `drift_route_accuracy`: `metrics.methods[].route_accuracy` (rate object).
- `drift_unsafe_acceptance`: `metrics.methods[].unsafe_acceptance` (rate object).
- `drift_type_heatmap`: `metrics.methods[].drift_types.<drift_type>.unsafe_acceptance` (rate object).
- `route_confusion_matrix`: `metrics.methods[].route_confusion.labels[]` and `counts[][]`.
- `patch_recall`: `metrics.methods[].patch_recall` (rate object).
- `threshold_sensitivity`: `metrics.thresholds[].{threshold,route_accuracy,unsafe_acceptance}`.
- `publicqa_quality`: `metrics.methods[].quality.exact_match` (rate object) and `.quality.{f1,recall_at_5}` (bounded-mean objects). Bounded means may have nullable CI bounds with `ci_method: null` when the aggregator has not run a valid interval procedure; Wilson intervals are prohibited for them.
- `publicqa_latency`: `metrics.methods[].latency.p95_wall_clock_ms` (scalar object).
- `publicqa_tokens`: `metrics.methods[].tokens.{effective_prompt,saved_prompt,completion}_per_sample` (scalar objects).
- `quality_cost_scatter`: the `f1` and `effective_prompt_per_sample` paths above.
- `paired_delta_forest`: `metrics.paired_deltas[]` (paired-delta objects).
- `run_progress`: the separate progress contract below.
- `tracecag_routing`: `routing_spec.nodes[]` and `routing_spec.edges[]` from the version-controlled routing JSON.

Each method object requires stable `method_id` and display `label`. Threshold entries require numeric `threshold` and the two rate objects. Confusion labels are route IDs; `counts` is a square non-negative integer matrix in the same row/column label order.

Before a research partial summary exists, runner-log parsing emits a separate `tracecag.progress-summary.v1` contract:

```json
{
  "schema_version": "tracecag.progress-summary.v1",
  "run_id": "day-01-20260713T120000Z",
  "stage_id": "full",
  "suite_id": "hotpotqa_64",
  "target_count": 64,
  "observations": [{"sample_id": "hp-0001", "completed_at": "2026-07-13T12:01:02Z", "elapsed_seconds": 62.0, "completed_count": 1}],
  "availability": "ready"
}
```

An observation is valid only when the parser sees the runner's terminal sample marker, its `sample_id` is unique within `(run_id, stage_id)`, timestamps/counts are monotonic, and `completed_count <= target_count`. This validated observation count is authoritative for the live trigger and `run_progress`; a later research partial summary must match it before research figures become live-eligible.

Absent metrics are nullable and accompanied by `availability: pending|ready|invalid`; zero is always a legitimate value. Missing series produce a labelled `Pending scheduled evaluation` panel without placeholder numbers. Pending may be panel- or series-level as declared by the registry. The renderer must not substitute values, combine suites, or infer missing results.

Suite identity is explicit: `driftbench_v2_smoke_24`, `driftbench_legacy_122`, `driftbench_v2_240`, or a named Public-QA/sensitivity suite. It is never inferred from `n`. A figure contains one suite unless its registry entry explicitly permits paired comparisons. Mixed input is rejected, the prior manifest remains published, and dashboard status reports the validation error.

## Research presentation standard

All plots use Matplotlib's deterministic `Agg` backend and a pinned Matplotlib/Seaborn dependency range. They use an embedded or documented serif font with DejaVu Serif fallback, a color-blind-safe palette, restrained grid lines, explicit units, visible sample size, and captions that identify the confidence interval method. Vector output embeds fonts where the backend permits. Axis limits are metric-aware, declared in the registry, and never visually exaggerate small differences. Figures use constrained layout without `bbox_inches="tight"`; PNG uses the registry's exact physical size at 300 DPI (for example, 7.2 x 4.2 inches produces 2160 x 1260 pixels). No 3D effects are allowed.

Each manifest contains `schema_version`, `manifest_version`, and per-figure `artifact_version`, status, figure ID, alt text, caption, creation timestamp, `run_id`, `stage_id`, `suite_id`, completed/target counts, renderer version, source dataset hash, configuration hash, metric, and confidence-interval method. Each figure has `artifacts`, keyed by `png`, `svg`, or `pdf`; every entry contains `format`, allowlisted `filename`, SHA-256 of exact bytes, `media_type`, and byte size.

The aggregation layer computes `dataset.source_dataset_hash` as SHA-256 of canonical JSON containing `{dataset_id, revision, rows}`, where `rows` are the exact normalized input rows sorted by stable row ID, excluding paths and mtimes. The renderer copies and validates this supplied digest; raw rows do not cross the figure-summary boundary. `configuration_hash` is SHA-256 of the required normalized `config` object shown above, including explicit nulls. `artifact_version` hashes canonical JSON containing the exact normalized figure input subtree, source/config hashes, renderer and style versions, dimensions, DPI, backend, and output formats. `manifest_version` hashes the canonical manifest entries excluding `created_at`, `manifest_version`, and transient render status; it changes only when published artifact bytes or stable metadata change.

## Dashboard behavior

Research chart containers become image components sourced from Python artifacts. `GET /api/figures` returns the manifest and render status; `GET /figures/<allowlisted-filename>` serves only manifest-listed files with the correct PNG/SVG/PDF content type, `ETag`, and immutable cache headers. Unknown files return 404 and traversal is rejected. The existing event stream emits a `figures_changed` event containing `manifest_version`; the browser refetches the manifest and uses `/figures/<filename>?v=<artifact_version>`.

Existing KPI text, progress state, runner controls, and logs remain HTML. KPI and research-table values come directly from Python summary fields. JavaScript may format supplied values, refresh/download an artifact, or show metadata; it performs no aggregation, CI calculation, scale calculation, chart geometry, or metric derivation. Existing client chart builders for bars, scatter, heatmap, stacked routes/tokens, forest plots, confusion matrices, and timelines are removed.

While a new image is rendering, the previous valid image remains displayed with a small updating indicator. If no valid artifact exists, the dashboard shows an accessible pending/error state. Every image uses manifest-provided alt text/caption and fixed aspect-ratio dimensions to avoid layout shift. SVG and PDF download actions appear only when those finalized formats exist. A failed image request keeps the prior DOM image and exposes a retry action.

### Responsive research-figure layout

The dashboard uses a 12-column hierarchy rather than allowing arbitrary figure widths. Primary research figures—route accuracy, unsafe acceptance, confusion matrix, and threshold sensitivity—span all 12 columns. Compatible secondary Public-QA figures share equal `6/12` widths, but retain independent content-driven heights; grid rows use start alignment and never stretch a shorter card to match a taller sibling. Otherwise each figure spans the full row. Below 900 px every figure spans one column.

The content canvas is centered with a 1440 px maximum width. Figure cards use compact 16 px body padding and 16–20 px header padding, with download actions styled as small controls rather than oversized text links. Images fill the available card width while preserving their intrinsic aspect ratio. Captions sit directly below the image with compact spacing. The Matplotlib canvas owns the scientific plot whitespace; the dashboard must not add large duplicate margins around it.

## Validation and tests

Unit tests validate source-summary requirements, filenames, registry uniqueness, manifest metadata, pending panels, zero-versus-missing values, explicit suite isolation, canonical hash/checksum determinism, and manifest-last atomic replacement. Fake-clock tests cover the exact five-sample and 30-second boundaries, per-run/stage reset, run switching, arrivals during rendering, serialization, and coalescing. Lifecycle tests cover restart discovery, failed/cancelled stages, failed artifact or manifest saves, cleanup, and preservation of the prior version.

Figure tests use deterministic fixtures and structurally verify expected labels, units, sample sizes, CI method, point/error-bar counts, axis bounds, output dimensions, valid PNG/SVG/PDF structure, and manifest-to-file checksums. Contract tests ensure captions and displayed values match the input summary and that suite identities cannot be mixed.

Dashboard/API tests cover content types, ETags/cache headers, unknown files, path traversal, status/error payloads, accessible alt text, pending/error states, finalized-button visibility, cache-busting only after successful publication, and absence of browser-side metric/geometry builders. Browser smoke tests cover live updates, image failure, and a manifest change during image load.

## Non-goals

This change does not alter benchmark metrics, thresholds, model calls, dataset scheduling, or the paper's claims. It may extend aggregation output with nullable values, counts, bounds, identity, and availability metadata, but may not change their meaning. Interactive tooltips and client-side chart manipulation are intentionally excluded; traceability and publication reproducibility take priority.
