# Strict Benchmark KG Isolation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make public-QA benchmark stages fail before paid inference if the frozen Kuzu snapshot cannot be copied, identified, or opened without recovery/reseeding.

**Architecture:** Keep the canonical snapshot read-only, create an owner-writable disposable copy per stage, and bind the subprocess to that copy. Benchmark strict mode disables KG rebuild/reseed recovery; report provenance proves the source and pre-run copy identities before resume accepts an artifact.

**Tech Stack:** Python 3.12, Kuzu, pytest, JSON benchmark reports.

---

## Chunk 1: Strict KG contract

### Task 1: Add failing runner and service tests

**Files:**
- Modify: `ai-service/tests/trace_cag/test_daily_benchmark_runner.py`
- Create: `ai-service/tests/trace_cag/test_kg_service_benchmark_strict.py`

- [x] Test that the stage subprocess receives a distinct, writable temporary KG with the expected pre-hash.
- [x] Test that canonical KG remains read-only and unchanged.
- [x] Test that resume rejects missing/false isolation provenance.
- [x] Test that strict KG mode raises instead of rebuilding or seeding.

### Task 2: Implement isolated working-copy validation

**Files:**
- Modify: `ai-service/model-development/benchmark/run_daily_benchmark.py`

- [x] Make only copied files/directories owner-writable.
- [x] Hash the working copy immediately before subprocess execution.
- [x] Abort before subprocess on path, permission, or hash mismatch.
- [x] Record pre/post hashes, distinct path, writable state, and source invariance.
- [x] Require all provenance fields when resuming.

### Task 3: Disable benchmark recovery and reseeding

**Files:**
- Modify: `ai-service/api/services/kg_service_v3.py`
- Modify: `ai-service/model-development/benchmark/run_daily_benchmark.py`

- [x] Add benchmark strict-mode environment flags.
- [x] Raise the original initialization/runtime error rather than rebuilding.
- [x] Reject an empty/missing benchmark snapshot rather than seeding defaults.

## Chunk 2: Verification and cost gate

### Task 4: Verify locally

- [x] Run focused KG/runner tests and the complete benchmark-focused suite.
- [x] Run an extractive local stage probe against a temporary snapshot copy.
- [x] Confirm canonical snapshot SHA-256 and mode remain unchanged.
- [x] Request test-writer and code-reviewer review.

### Task 5: Allow paid execution only after green review

- [ ] Reset stale operational status through the normal `--resume` flow.
- [ ] Run HotpotQA preflight `n=5` with strict provider/fallback settings.
- [ ] Inspect validation, provider errors, KG provenance, route decisions, and estimated cost before starting `n=64`.
