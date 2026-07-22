# Fair TRACE-CAG Evaluation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove evaluation leakage while preserving cache behavior and producing stable cold-quality/warm-cache metrics.

**Architecture:** Keep gold labels in the evaluator, freeze learned retrieval during evaluation, use a clean frozen KG, and fail the stage on provider degradation. Reuse current runtime/reporting helpers; add no dependencies.

**Tech Stack:** Python 3.12, pytest, Kuzu, Docker Compose.

---

## Chunk 1: Oracle-free runtime

- [ ] Add tests proving public-QA metadata excludes supporting titles and answers.
- [ ] Remove supporting titles from runtime metadata.
- [ ] Make IRCoT selection depend only on observable context/query signals.
- [ ] Prevent online ranker observation during public evaluation.

## Chunk 2: Honest metrics and failure handling

- [ ] Add cold-only quality and warm-only cache summaries.
- [ ] Keep retrieval labels in evaluator-side joins only.
- [ ] Fail immediately on provider bypass and preserve partial diagnostics.

## Chunk 3: Clean KG and operations

- [ ] Build a frozen evaluation KG without benchmark-derived concepts.
- [ ] Update manifest hash and verify isolated-copy preflight.
- [ ] Check Docker daemon and service health.
- [ ] Run focused tests, extractive smoke, code review, then paid preflight only.
