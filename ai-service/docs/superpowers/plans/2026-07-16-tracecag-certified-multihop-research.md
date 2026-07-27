# TRACE-CAG Certified Multi-Hop Research Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test bounded second-hop evidence expansion while preserving TRACE-CAG certificate, mutation, and provenance guarantees.

**Architecture:** Reorder the existing frozen candidate pool only for benchmark multi-hop tasks. Preserve rank one, follow explicit title links from the top-three seeds, deduplicate by title, then apply the existing evidence budget and certificate pipeline. The feature is off by default behind `TRACECAG_SECOND_HOP_INTERLEAVE`.

**Tech Stack:** Python 3, existing TRACE-CAG benchmark ranking, pytest.

---

### Task 1: Add guarded second-hop interleaving

**Files:**
- Modify: `api/services/trace_cag/benchmark/ranking.py`
- Modify: `api/services/trace_cag/retrieve.py`
- Create: `tests/trace_cag/test_second_hop_interleave.py`

- [ ] Test disabled behavior, rank-one preservation, explicit-link insertion, deduplication, and provenance field preservation.
- [ ] Add the smallest pure ordering helper behind the research flag.
- [ ] Apply it before the existing diverse evidence selector.
- [ ] Run focused retrieval, certificate, recheck, and invalidation tests.

### Task 2: End-to-end research gate

- [ ] Run a small fixed Day 1 development sample with the flag on.
- [ ] Run Day 2 cross-check without tuning.
- [ ] Compare EM/F1, R@5, MRR, NDCG@5, IRCoT contract pass, latency, and provider calls.
- [ ] Keep the flag off unless answer quality is non-regressing and paired retrieval gains persist.
