# Production KG Isolation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild a clean production KG and prevent benchmark data or raw retrieval context from reaching Lexi chat.

**Architecture:** Physically separate benchmark/runtime paths, reject benchmark namespaces at production ingestion/startup, and replace chat extractive fallback with a safe non-cacheable response. Rebuild into a validated replacement DB and invalidate old response-cache policy.

**Tech Stack:** Python 3.12, KuzuDB, FastAPI, Redis, pytest.

---

## Chunk 1: Regression contracts

### Task 1: Write failing isolation and fallback tests

**Files:**
- Modify: `ai-service/tests/trace_cag/test_generate_node.py`
- Modify: `ai-service/tests/test_lexi_chat_routes.py`
- Create: `ai-service/tests/trace_cag/test_production_kg_isolation.py`
- Create: `ai-service/tests/test_seed_benchmark_kg_isolation.py`

- [x] Assert provider outage returns a safe response without retrieval text.
- [x] Assert degraded fallback is not cached.
- [x] Assert streaming provider outage returns the safe response and is not cached.
- [x] Assert runtime validation rejects `concept:benchmark.*`.
- [x] Assert benchmark seeding refuses runtime DB/source destinations.
- [x] Run focused tests and confirm failures match the missing contracts.

## Chunk 2: Physical isolation and runtime guard

### Task 2: Separate benchmark storage

**Files:**
- Modify: `ai-service/model-development/scripts/seed_benchmark_kg.py`
- Delete: `ai-service/data/kg/benchmark_entities.json`
- Modify: `ai-service/.env.example`

- [x] Require explicit `--db-path` and `--output-file` benchmark paths.
- [x] Reject paths equal to or nested under runtime KG destinations.

### Task 3: Add production KG invariants

**Files:**
- Modify: `ai-service/api/services/kg_data_loader.py`
- Modify: `ai-service/api/services/kg_service_v3.py`
- Test: `ai-service/tests/trace_cag/test_production_kg_isolation.py`

- [x] Reject benchmark namespaces before a production merge.
- [x] Sync only explicit runtime source filenames/directories and test that an unlisted JSON file is ignored.
- [x] Check the initialized production graph before readiness succeeds.
- [x] Restrict automatic rebuild to recognized corruption failures.

## Chunk 3: Safe degradation and cache rollover

### Task 4: Isolate chat fallback

**Files:**
- Modify: `ai-service/api/services/trace_cag/generate.py`
- Modify: `ai-service/api/services/lexi_chat_service.py`
- Modify: `ai-service/api/services/trace_cag/cache_utils.py`
- Test: `ai-service/tests/trace_cag/test_generate_node.py`

- [x] Use fixed Lexi degraded text for non-benchmark chat.
- [x] Skip response-cache writes for unavailable/degraded generation in regular and streaming chat.
- [x] Bump `_POLICY_VERSION` to invalidate existing cached responses.

## Chunk 4: Clean rebuild and verification

### Task 5: Add a guarded rebuild command

**Files:**
- Create: `ai-service/scripts/rebuild_runtime_kg.py`
- Create: `ai-service/tests/test_rebuild_runtime_kg.py`

- [x] Build a new Kuzu DB from runtime sources.
- [x] Validate zero benchmark IDs and a non-empty expected runtime graph.
- [x] Quarantine the old DB and atomically promote the validated replacement.
- [x] Provide dry-run/validate-only modes and refuse broad/unresolved paths.
- [x] Discard existing `Mastery` nodes/edges; do not migrate them from the contaminated DB.

### Task 6: Verify and review

- [x] Run focused pytest suites.
- [x] Run the rebuild against a temporary copy, then validate the actual runtime target.
- [ ] Stop production writers, rebuild and promote the production target, restart, then verify readiness and zero benchmark nodes.
- [x] Run the complete TraceCAG test suite.
- [x] Request test-writer, security-reviewer, and code-reviewer review.
