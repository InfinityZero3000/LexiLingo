# Offline Bridge Rerank Probe Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate bridge-aware reranking against frozen Day 1–2 artifacts without touching production.

**Architecture:** One stdlib CLI joins report observations with frozen dataset labels, applies deterministic rerankers, and emits JSON. One focused test covers label isolation and metric behavior.

**Tech Stack:** Python 3 stdlib, pytest.

---

### Task 1: Implement and validate the offline probe

**Files:**
- Create: `model-development/scripts/probe_bridge_rerank.py`
- Create: `tests/benchmark/test_probe_bridge_rerank.py`

- [x] Write a failing test for bridge scoring and paired metric output.
- [x] Implement tokenization, three scorers, ranking metrics, report/dataset join, and CLI JSON output.
- [x] Run the focused test.
- [x] Run the probe on Day 1–2 and save the output under `model-development/reports/benchmarks/analysis/`.
- [x] Interpret only observed paired deltas and candidate-pool upper bounds.
