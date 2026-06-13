# TRACE-CAG Unified Benchmark Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic public-QA benchmark with a modular package that evaluates production `ai-service` TRACE-CAG for public QA and drift safety.

**Architecture:** A thin CLI selects a protocol, typed dataset loaders create requests, one runtime adapter invokes `TraceCAGPipeline`, protocol modules orchestrate runs, independent metric modules aggregate observations, and reporting writes reproducible manifests. Production TRACE-CAG receives only backwards-compatible raw-state instrumentation and benchmark-only state hints.

**Tech Stack:** Python 3.12, asyncio, dataclasses, pytest, LangGraph TRACE-CAG pipeline, KuzuDB, JSON/JSONL, Bash compatibility wrappers.

---

## Chunk 1: Benchmark Core

### Task 1: Add typed configuration, catalog, and schemas

**Files:**
- Create: `model-development/benchmark/tracecag_bench/__init__.py`
- Create: `model-development/benchmark/tracecag_bench/config.py`
- Create: `model-development/benchmark/tracecag_bench/catalog.py`
- Create: `model-development/benchmark/tracecag_bench/schemas.py`
- Create: `tests/benchmark/test_config_catalog.py`

- [ ] Write tests for Qwen/Groq defaults, environment aliases, dataset lookup, mode lookup, and secret-redacted config serialization.
- [ ] Run `pytest tests/benchmark/test_config_catalog.py -q` and verify failure.
- [ ] Implement immutable config and typed catalog/schema objects.
- [ ] Run the focused test and verify it passes.

### Task 2: Add validated dataset loaders and migrate DriftBench

**Files:**
- Create: `model-development/benchmark/tracecag_bench/datasets/__init__.py`
- Create: `model-development/benchmark/tracecag_bench/datasets/public_qa.py`
- Create: `model-development/benchmark/tracecag_bench/datasets/driftbench.py`
- Create: `model-development/datasets/benchmarks/trace_driftbench/train.jsonl`
- Create: `model-development/datasets/benchmarks/trace_driftbench/calibration.jsonl`
- Create: `model-development/datasets/benchmarks/trace_driftbench/test.jsonl`
- Create: `model-development/datasets/benchmarks/trace_driftbench/manifest.json`
- Modify: `model-development/datasets/benchmarks/manifest.json`
- Create: `tests/benchmark/test_datasets.py`

- [ ] Write tests for `context_docs`, accepted-answer aliases, deterministic sampling, supporting-title deduplication, cluster ordering, and malformed-row errors.
- [ ] Run `pytest tests/benchmark/test_datasets.py -q` and verify failure.
- [ ] Implement loaders and copy normalized DriftBench splits from the existing paper harness.
- [ ] Generate manifest counts and SHA-256 hashes.
- [ ] Run the focused tests and verify they pass.

### Task 3: Implement correct independent metrics

**Files:**
- Create: `model-development/benchmark/tracecag_bench/metrics/__init__.py`
- Create: `model-development/benchmark/tracecag_bench/metrics/text.py`
- Create: `model-development/benchmark/tracecag_bench/metrics/retrieval.py`
- Create: `model-development/benchmark/tracecag_bench/metrics/cache.py`
- Create: `model-development/benchmark/tracecag_bench/metrics/safety.py`
- Create: `model-development/benchmark/tracecag_bench/metrics/latency.py`
- Create: `tests/benchmark/test_metrics.py`

- [ ] Write table-driven tests for EM/F1 aliases, Recall@K, Precision@K, MRR, nDCG, uncertain safety exclusion, route accuracy, patch recall, cache slices, and percentiles.
- [ ] Run `pytest tests/benchmark/test_metrics.py -q` and verify failure.
- [ ] Implement pure metric functions with zero runtime dependencies.
- [ ] Run the focused tests and verify they pass.

## Chunk 2: Production Runtime Contract

### Task 4: Add benchmark-observable cache gate metadata

**Files:**
- Modify: `api/services/trace_cag/state.py`
- Modify: `api/services/trace_cag/l1_state_cache.py`
- Modify: `api/services/trace_cag/nodes_v2.py`
- Create: `tests/trace_cag/test_cache_gate_benchmark_metadata.py`

- [ ] Write tests asserting raw state contains PCC/SCAR reasons, thresholds, risk, routing latency, and benchmark state hints.
- [ ] Run the focused test and verify failure.
- [ ] Add `cache_gate_meta` to state and return it from every cache-gate branch.
- [ ] Read state hints only from a `_tracecag_state` benchmark namespace.
- [ ] Preserve normal production derivation when hints are absent.
- [ ] Run cache-gate and L1 tests.

### Task 5: Add deterministic runtime reset and adapter

**Files:**
- Create: `model-development/benchmark/tracecag_bench/runtime/__init__.py`
- Create: `model-development/benchmark/tracecag_bench/runtime/reset.py`
- Create: `model-development/benchmark/tracecag_bench/runtime/ai_service.py`
- Create: `tests/benchmark/test_runtime_adapter.py`

- [ ] Write fake-pipeline tests for metadata mapping, provider classification, errors, and reset scopes.
- [ ] Run the focused test and verify failure.
- [ ] Implement cache/KG/ranker resets using explicit known production module state.
- [ ] Implement the sole `TraceCAGPipeline.analyze` adapter.
- [ ] Ensure public QA sends `context_docs`; ensure drift sends learner/state hints.
- [ ] Run focused adapter tests and existing TraceCAG cache tests.

## Chunk 3: Protocols and Reporting

### Task 6: Implement KG preflight and public-QA protocol

**Files:**
- Create: `model-development/benchmark/tracecag_bench/kg/__init__.py`
- Create: `model-development/benchmark/tracecag_bench/kg/preflight.py`
- Create: `model-development/benchmark/tracecag_bench/protocols/__init__.py`
- Create: `model-development/benchmark/tracecag_bench/protocols/public_qa.py`
- Create: `tests/benchmark/test_kg_preflight.py`
- Create: `tests/benchmark/test_public_qa_protocol.py`

- [ ] Write tests for healthy/degraded KG behavior and candidate-pool versus KG-only request construction.
- [ ] Run focused tests and verify failure.
- [ ] Implement read-only KG preflight.
- [ ] Implement cold/warm and query-cluster execution through the runtime adapter.
- [ ] Aggregate generation, real retrieval-trace, cache, provider, KG, and latency metrics.
- [ ] Run focused tests.

### Task 7: Implement drift-safety protocol and calibration

**Files:**
- Create: `model-development/benchmark/tracecag_bench/protocols/drift_safety.py`
- Create: `tests/benchmark/test_drift_safety_protocol.py`

- [ ] Write tests for base-first cluster execution, cluster isolation, uncertain exclusion, route mapping, and calibration/test separation.
- [ ] Run focused tests and verify failure.
- [ ] Implement production-pipeline drift execution.
- [ ] Implement calibration threshold selection under unsafe budget without test leakage.
- [ ] Aggregate per-method and per-drift-category metrics.
- [ ] Run focused tests.

### Task 8: Implement reproducible reports and CLI

**Files:**
- Create: `model-development/benchmark/tracecag_bench/reporting/__init__.py`
- Create: `model-development/benchmark/tracecag_bench/reporting/json_report.py`
- Create: `model-development/benchmark/tracecag_bench/reporting/console.py`
- Create: `model-development/benchmark/tracecag_bench/cli.py`
- Create: `model-development/benchmark/benchmark.py`
- Create: `tests/benchmark/test_reporting_cli.py`

- [ ] Write tests for report manifests, partial reports, provider validation, non-comparable historical retrieval labels, and CLI argument parsing.
- [ ] Run focused tests and verify failure.
- [ ] Implement JSON/JSONL and console reporters.
- [ ] Implement `public-qa`, `drift-safety`, and `all` commands.
- [ ] Return non-zero after writing reports when run validation fails.
- [ ] Run focused tests.

## Chunk 4: Compatibility and Verification

### Task 9: Replace the monolith with compatibility wrappers

**Files:**
- Modify: `model-development/benchmark/benchmark_public_qa.py`
- Modify: `model-development/benchmark/run_benchmark_all_datasets.sh`
- Create: `model-development/benchmark/README.md`
- Modify: `model-development/.env`

- [ ] Preserve supported legacy arguments and translate them to the new CLI.
- [ ] Update the all-datasets shell wrapper to run `benchmark.py public-qa`.
- [ ] Set/document `GROQ_MODEL=qwen/qwen3-32b` without changing secrets.
- [ ] Document candidate-pool, KG-only, DriftBench, calibration, and live smoke commands.
- [ ] Verify `--help` for new and compatibility CLIs.

### Task 10: Run the complete offline verification suite

**Files:**
- Test: `tests/benchmark/`
- Test: `tests/trace_cag/test_cache_gate_l1.py`
- Test: `tests/trace_cag/test_l1_state_cache.py`
- Test: `tests/trace_cag/test_l1_drift_probe_decisions.py`

- [ ] Run `pytest tests/benchmark -q`.
- [ ] Run the focused TraceCAG cache suite.
- [ ] Run `python model-development/benchmark/benchmark.py public-qa --dataset hotpotqa --n 1 --generation-policy extractive --allow-degraded-provider`.
- [ ] Run `python model-development/benchmark/benchmark.py drift-safety --split test --n-clusters 1 --generation-policy extractive --allow-degraded-provider`.
- [ ] Inspect both reports for dataset hash, KG snapshot, retrieval trace metrics, cache state, and provider validity.

### Task 11: Run optional live Groq smoke validation

**Files:**
- Output: `model-development/reports/benchmarks/`

- [ ] Confirm configured model is `qwen/qwen3-32b` without printing keys.
- [ ] Run one public-QA sample with primary-provider validation.
- [ ] Record whether the live run passed, failed due to quota/network, or used an unexpected fallback.
- [ ] Do not weaken validation to make a failed live run appear successful.
