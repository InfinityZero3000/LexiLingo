# TRACE-CAG Full Benchmark Run Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the TRACE-CAG benchmark end to end, identify real bottlenecks, fix confirmed issues minimally, and rerun the benchmark.

**Architecture:** Use the existing `model-development/benchmark/benchmark.py` CLI and existing JSON report format. The workflow is offline sanity, mini live run, report analysis, minimal fixes if evidence demands them, focused verification, then full live run.

**Tech Stack:** Python 3.12 venv, pytest, TRACE-CAG benchmark CLI, Groq `qwen/qwen3-32b`, JSON reports, shell logs.

---

## File Structure

- Read: `docs/superpowers/specs/2026-07-04-tracecag-full-benchmark-run-design.md`
- Read: `model-development/benchmark/benchmark.py`
- Read: `model-development/benchmark/tracecag_bench/cli.py`
- Read: `model-development/benchmark/tracecag_bench/reporting/json_report.py`
- Output: `model-development/reports/benchmarks/*.json`
- Output: `model-development/reports/benchmarks/logs/*.log`
- Modify only if benchmark evidence proves a bug: benchmark runtime, reporting, cache reset, provider classification, or TRACE-CAG runtime files directly implicated by logs.

## Chunk 1: Baseline Checks

### Task 1: Confirm workspace and offline tests

**Files:**
- Read: git status
- Test: `tests/benchmark/`
- Test: `tests/trace_cag/test_cache_gate_benchmark_metadata.py`
- Test: `tests/trace_cag/test_cache_gate_l1.py`
- Test: `tests/trace_cag/test_l1_state_cache.py`
- Test: `tests/trace_cag/test_l1_drift_probe_decisions.py`

- [ ] Check `git status --short` and note unrelated dirty files.
- [ ] Run:

```bash
venv/bin/python -m pytest tests/benchmark \
  tests/trace_cag/test_cache_gate_benchmark_metadata.py \
  tests/trace_cag/test_cache_gate_l1.py \
  tests/trace_cag/test_l1_state_cache.py \
  tests/trace_cag/test_l1_drift_probe_decisions.py -q
```

- [ ] Expected: tests pass before any live benchmark starts.

## Chunk 2: Mini Live Run

### Task 2: Run all benchmark protocols with small n

**Files:**
- Output: `model-development/reports/benchmarks/logs/tracecag-mini-live-<timestamp>.log`
- Output: benchmark JSON reports in `model-development/reports/benchmarks/`

- [ ] Create a timestamped log path.
- [ ] Run:

```bash
venv/bin/python model-development/benchmark/benchmark.py all \
  --n 5 \
  --cache-repeats 2 \
  --generation-policy auto \
  --evidence-mode candidate_pool \
  --provider groq \
  --model qwen/qwen3-32b
```

- [ ] Capture stdout and stderr to the log.
- [ ] If the command exits non-zero, inspect reports and log before changing code.

## Chunk 3: Report Analysis

### Task 3: Summarize bottlenecks from JSON reports

**Files:**
- Read: newly generated `model-development/reports/benchmarks/*.json`
- Read: mini live log

- [ ] For each report, record `run_validation.passed`.
- [ ] For public QA, record F1, R@5, MRR@5, cache hit, warm hit, L1 hit, mean/P50/P95 latency, providers, fallback rate, errors.
- [ ] For drift safety, record route accuracy, unsafe acceptance, patch recall, fallback rate, routing overhead, latency, errors.
- [ ] Treat provider fallback, `bypass`, errors, failed validation, suspicious cache leakage, and high routing overhead as possible bottlenecks.
- [ ] Do not tune ranking quality from `n=5` alone.

## Chunk 4: Minimal Fixes

### Task 4: Fix only confirmed defects

**Files:**
- Modify only the file named by the log/report root cause.
- Add or update the smallest focused test beside existing tests.

- [ ] Grep every caller of the function before editing it.
- [ ] Write or update one focused failing test.
- [ ] Implement the smallest root-cause fix.
- [ ] Run the focused test.
- [ ] Run the baseline focused test suite from Chunk 1.
- [ ] Commit only files touched for the fix.

## Chunk 5: Rerun and Full Benchmark

### Task 5: Rerun affected slice, then run full benchmark

**Files:**
- Output: `model-development/reports/benchmarks/logs/tracecag-full-live-<timestamp>.log`
- Output: benchmark JSON reports in `model-development/reports/benchmarks/`

- [ ] If a fix was made, rerun the failed mini slice.
- [ ] Run:

```bash
venv/bin/python model-development/benchmark/benchmark.py all \
  --n 20 \
  --cache-repeats 2 \
  --generation-policy auto \
  --evidence-mode candidate_pool \
  --provider groq \
  --model qwen/qwen3-32b
```

- [ ] Capture stdout and stderr to the full live log.
- [ ] Summarize final reports, bottlenecks, fixes, and unresolved risks.
