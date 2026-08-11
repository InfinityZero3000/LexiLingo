# ICTA TRACE-CAG Benchmark Execution Plan

> **For agentic workers:** REQUIRED: Execute in the current session with checkpoints; use reviewer agents only at review gates.

**Goal:** Produce validated TRACE-CAG benchmark artifacts and evidence for the eight-page ICTA paper.

**Architecture:** Reuse the existing seven-stage resumable benchmark runner. Start only Redis, freeze and verify inputs before paid calls, fail closed on provider/KG/artifact mismatch, then aggregate results for the paper.

**Tech Stack:** Python 3.12, pytest, Docker Compose, Redis, Kuzu, Groq qwen/qwen3-32b.

---

## Chunk 1: Environment and protocol freeze

**Files:**
- Read: `docker-compose.yml`
- Read: `model-development/benchmark/daily_benchmark_manifest.json`
- Create: `model-development/reports/benchmarks/daily/protocol-lock.json`

- [ ] Check Docker daemon, Compose, Python/venv, disk/RAM, API-key presence, required datasets, and KG hash without printing secrets.
- [ ] Start `redis` with `MONGO_EXPRESS_PASSWORD=unused docker compose up -d redis` and require healthy status plus `redis-cli ping`.
- [ ] Run the focused benchmark/TRACE-CAG pytest suites.
- [ ] Run provider, KG-isolation, dataset-schema, and evaluator-leakage preflights.
- [ ] Verify the exact manifest/dataset/KG SHA-256 values listed in the approved spec; stop on any mismatch.
- [ ] Write canonical sorted `protocol-lock.json` containing the clean commit or archived binary-diff hash, dependency-lock hash, prompt hashes, `max_tokens=96`, and frozen input hashes; compute its SHA-256 separately as the protocol ID in run/artifact metadata.
- [ ] Assert from preflight artifacts: seed 42, observed provider `groq`, observed model `qwen/qwen3-32b`, candidate-pool evidence, two cache repeats, serial temperature-0 generation, max_tokens 96, 30s timeout, frozen 401/503 retry handling, cache reset, cold/warm separation, no fallback, and no degraded provider.

## Chunk 2: Real benchmark

**Files:**
- Execute: `model-development/benchmark/run_daily_benchmark.py`
- Write: `model-development/reports/benchmarks/daily/day-*/`

- [ ] Run day 1 HotpotQA; require `n=5` preflight validation before full n=64.
- [ ] Run day 2 2Wiki; require preflight before full n=64.
- [ ] Run day 3 query-clusters; require preflight before full n=32.
- [ ] Run day 4 MuSiQue; require preflight before full n=500.
- [ ] Run day 5 full TRACE-CAG on DriftBench-240.
- [ ] Run day 6 on the identical frozen DriftBench input with mandatory `l2_only`, `exact_cache`, `lexical_overlap_cache`, `state_semantic_cache`, `version_aware_cache`, `trace_no_pcc`, `trace_no_graph_scope`, and `trace_no_scar`; include `embedding_cache` only after its recorded preflight passes. Enforce the same candidate/top-k/artifact/L2/state/threshold routing budget, with each ablation changing only its named component.
- [ ] Run day 7 threshold sensitivity and aggregate paper tables without tuning the test-set primary result.
- [ ] Stop and diagnose on any validation/provider/KG failure; resume only when hashes match.
- [ ] Invalidate and restart a final stage after any code/config/KG change; preserve prior attempts immutably, append only missing stable `(dataset,item,mode,repeat)` keys, and invalidate duplicate keys.

## Chunk 3: Evidence and paper handoff

**Files:**
- Create: `model-development/reports/benchmarks/daily/comparison-report.md`
- Modify: ICTA DOCM deliverable under `model-development/pdf/`

- [ ] Build and verify the canonical JSONL artifact hash chain; recompute every referenced hash, protocol ID, exclusion, unique observation key, and table/figure provenance.
- [ ] Compare new results with May/June 2026 runs contextually; select “best” only among compatible protocol tuples.
- [ ] Produce Wilson intervals, cluster-bootstrap DriftBench and item-bootstrap public-QA effects/95% CIs, applicable paired tests with Holm correction, plus per-drift, cold/warm latency, error-analysis, and provenance tables.
- [ ] Audit L0/L1/L2, PCC, SCAR-L1, drift, invalidation, and atomic snapshot claims against code/tests.
- [ ] Draft the eight-page ICTA paper in the official DOCM template, preserving VBA/macros.
- [ ] Render every page, verify exactly eight pages, inspect all figures/tables/citations, and confirm macro presence.
- [ ] Run final scientific/code/document review and fix blocking findings.
