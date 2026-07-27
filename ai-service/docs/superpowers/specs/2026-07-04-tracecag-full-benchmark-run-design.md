# TRACE-CAG Full Benchmark Run Design

## Objective

Run a production-backed TRACE-CAG benchmark, monitor the results, identify real
bottlenecks, make only necessary fixes, then rerun the affected benchmark scope
and the full benchmark.

The run uses the existing benchmark CLI:

```text
model-development/benchmark/benchmark.py
```

This spec does not redesign the benchmark package. It defines the execution and
analysis workflow for this run.

## Current Context

The benchmark package already supports:

- `public-qa` for HotpotQA, 2WikiMultihopQA, MuSiQue, and `query_clusters`
- `drift-safety` for TRACE-DriftBench
- `all` to run all public QA datasets followed by drift safety
- strict provider validation through `run_validation`
- JSON reports under `model-development/reports/benchmarks/`

The repo currently has unrelated dirty Flutter files outside `ai-service`.
This run must not touch or commit those changes.

## Approved Approach

Use a two-stage live run:

1. Mini live preflight across all datasets.
2. Full live run after mini reports are clean or after minimal fixes.

This avoids wasting provider quota on a full run if provider validation,
fallback behavior, cache reset, or report wiring is already broken.

## Execution Plan

### Stage 1: Offline Sanity

Run the focused benchmark and TRACE-CAG cache tests:

```text
venv/bin/python -m pytest tests/benchmark \
  tests/trace_cag/test_cache_gate_benchmark_metadata.py \
  tests/trace_cag/test_cache_gate_l1.py \
  tests/trace_cag/test_l1_state_cache.py \
  tests/trace_cag/test_l1_drift_probe_decisions.py -q
```

The live benchmark should not start if this fails.

### Stage 2: Mini Live Benchmark

Run:

```text
venv/bin/python model-development/benchmark/benchmark.py all \
  --n 5 \
  --cache-repeats 2 \
  --generation-policy auto \
  --evidence-mode candidate_pool \
  --provider groq \
  --model qwen/qwen3-32b
```

Capture stdout/stderr to a timestamped log in:

```text
model-development/reports/benchmarks/logs/
```

### Stage 3: Bottleneck Analysis

Inspect every generated JSON report for:

- `run_validation.passed`
- provider fallback or `bypass` output
- mode-level `errors`
- latency mean, P50, P95, and routing overhead
- cold and warm cache hit rates
- L0 and L1 rates
- public QA F1, R@5, and MRR@5
- drift route accuracy, unsafe acceptance, patch recall, and fallback rate
- KG preflight status

Treat a bottleneck as actionable only if the report or log gives direct
evidence. Do not tune thresholds or ranking weights from one noisy mini sample.

### Stage 4: Minimal Fixes

Allowed fixes:

- provider/model classification bugs
- report validation or report parsing defects
- cache reset leakage
- benchmark CLI wiring defects
- clear runtime errors found in logs
- missing observability needed to diagnose the run

Avoid broad refactors, new abstractions, or ranking algorithm changes unless the
benchmark proves a root-cause bug.

Every non-trivial fix needs the smallest focused test that would fail without
the fix.

### Stage 5: Rerun

After any fix:

1. Run focused tests.
2. Rerun the failed mini benchmark slice.
3. Run the full benchmark:

```text
venv/bin/python model-development/benchmark/benchmark.py all \
  --n 20 \
  --cache-repeats 2 \
  --generation-policy auto \
  --evidence-mode candidate_pool \
  --provider groq \
  --model qwen/qwen3-32b
```

## Success Criteria

The task is complete when:

- focused tests pass
- mini live reports are analyzed
- any confirmed benchmark/runtime issue is fixed with a focused test
- full live benchmark completes or clearly fails due to external quota/network
- final reports are summarized with bottlenecks, fixes, and remaining risks

## Non-Goals

- No new benchmark framework
- No broad TRACE-CAG refactor
- No provider fallback masking to make reports pass
- No edits to unrelated Flutter files
