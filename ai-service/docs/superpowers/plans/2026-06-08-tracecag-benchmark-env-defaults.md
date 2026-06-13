# TRACE-CAG Benchmark Environment Defaults Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `model-development/benchmark/benchmark.py all` run the standard 100-sample Groq/Qwen benchmark with local Redis without repeating CLI options.

**Architecture:** Load `model-development/.env` before constructing the argument parser, then use environment-backed defaults for benchmark options. CLI arguments remain authoritative overrides. Keep production application configuration unchanged by scoping these defaults to the benchmark environment file and runner.

**Tech Stack:** Python, argparse, python-dotenv-style local loader, pytest, Docker Redis.

---

## Chunk 1: Environment-backed benchmark defaults

### Task 1: Add parser default tests

**Files:**
- Create: `tests/benchmark/test_cli_config.py`

- [x] Test that `all` defaults to 100 samples, Groq/Qwen, seed 42, and automatic generation.
- [x] Test that explicit CLI arguments override environment defaults.
- [x] Run the focused test and verify it fails before implementation.

### Task 2: Load CLI defaults from the benchmark environment

**Files:**
- Modify: `model-development/benchmark/tracecag_bench/config.py`
- Modify: `model-development/benchmark/tracecag_bench/cli.py`

- [x] Add safe environment parsers for integer, string, and boolean defaults.
- [x] Load `model-development/.env` before parser construction.
- [x] Map public QA, drift, provider, model, and validation defaults to environment variables.
- [x] Preserve command-line override behavior.
- [x] Run the focused tests and verify they pass.

### Task 3: Configure the standard local run

**Files:**
- Modify: `model-development/.env`
- Modify: `model-development/benchmark/README.md`

- [x] Configure Redis at `localhost:6379/1`.
- [x] Configure `n=100`, Qwen 3 32B, seed, profile, cache repeats, evidence mode, and validation defaults.
- [x] Document starting Redis and the minimal benchmark command.

### Task 4: Verify

**Files:**
- Test: `tests/benchmark`

- [x] Run all benchmark unit tests.
- [x] Inspect the `all` parser options without interrupting the active benchmark lock.
- [x] Confirm parsed defaults without starting a paid/live benchmark.
