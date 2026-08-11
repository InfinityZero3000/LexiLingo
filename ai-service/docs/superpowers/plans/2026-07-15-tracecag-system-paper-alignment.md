# TRACE-CAG System–Paper Alignment Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the production TRACE-CAG implementation match its state-certified reuse claims, validate the claims under drift, and regenerate an evidence-aligned eight-page ICTA paper.

**Architecture:** Production owns dependency capture, certificate validation, unified SCAR, reverse invalidation, typed patching, and optimistic recheck. Benchmark modes reuse those production primitives and add only workload orchestration and metrics. Work proceeds in vertical slices; each slice lands tests before the next slice begins.

**Tech Stack:** Python 3, pytest/pytest-asyncio, Redis, existing LangGraph TRACE-CAG pipeline, Kuzu, existing DriftBench runner, python-docx/DOCM builder.

**Design:** `docs/superpowers/specs/2026-07-15-tracecag-system-paper-alignment-design.md`

---

## Execution status (2026-07-16)

- Tasks 1–9: implemented; focused production, portable-service, benchmark-adapter, mutation, recheck, and patch tests pass.
- Task 10: implemented; controller ablations share the graph retriever/generator and pass isolation tests.
- Task 11: implemented in code; route-coverage gate, conservative safety metrics, and Wilson interval helper pass deterministic tests.
- Task 12: in progress. Redis-backed one-cluster smoke completed, but route gate is correctly blocking (L1 reuse, L1 patch, and optimistic recheck were not observed). The combined pytest command also exposes a legacy `tests` package collection collision; the current suites must run in separate processes. No frozen benchmark has been started.
- 2026-07-17 audit: the canonical request path passes 94 focused tests. Learner mutation invalidation is connected; KG and policy mutation hooks remain missing, so the broad mutation-aware claim is still blocked. Removed the dead `httpx_module` throttler argument and four now-unused imports.
- Tasks 13–14: pending final artifacts.
- No commits have been created; the workspace already contains unrelated user changes.

## File map

- Create `api/services/trace_cag/dependencies.py`: dependency event, trace compiler, canonical token-reader protocol.
- Create `api/services/trace_cag/invalidation.py`: reverse-edge registration, cleanup, and targeted invalidation using existing Redis access patterns.
- Modify `api/services/trace_cag/state.py`: certificate schema v3 and dependency/projection fields.
- Modify `api/services/trace_cag/l1_state_cache.py`: canonical hard gate and unified SCAR.
- Modify `api/services/trace_cag/cache_utils.py`: compile/store certificates, register reverse edges, recheck before serve, enforce patch postconditions.
- Modify production resolver nodes only where state is actually read; emit explicit events into `TraceCAGState`.
- Modify `model-development/benchmark/tracecag_bench/catalog.py`: controller-isolating ablation modes.
- Modify `model-development/benchmark/tracecag_bench/protocols/drift_safety.py`: preflight route-coverage gates and final metrics.
- Modify `model-development/benchmark/tracecag_bench/metrics/safety.py`: paired safety/route metrics and intervals.
- Modify `model-development/scripts/build_icta_paper.py`: evidence-aligned algorithms, equations, claims, tables, and figures.
- Preserve `model-development/pdf/TRACE-CAG_ICTA_2026_camera_ready_8pages_v5.docm`; generate a separate preview until visual QA passes.

## Chunk 1: Canonical state contract

### Task 1: Freeze current routing behavior

**Files:**
- Modify: `tests/trace_cag/test_l1_state_cache.py`
- Modify: `tests/trace_cag/test_l1_state_cache_certificate.py`
- Modify: `tests/trace_cag/test_cache_gate_l1.py`

- [ ] Add characterization tests for current exact reuse, near-hit patch, hard certificate rejection, empty candidate list, and L2 fallback.
- [ ] Add a regression proving L2 still returns `tutor_response` when cache quality admission fails.
- [ ] Run `venv/bin/pytest tests/trace_cag/test_l1_state_cache.py tests/trace_cag/test_l1_state_cache_certificate.py tests/trace_cag/test_cache_gate_l1.py -q` and record the baseline result.
- [ ] Commit only these characterization tests with `test(trace-cag): freeze cache routing behavior`.

### Task 2: Add dependency events and compiler

**Files:**
- Create: `api/services/trace_cag/dependencies.py`
- Create: `tests/trace_cag/test_dependency_trace.py`
- Modify: `api/services/trace_cag/state.py`

- [ ] Write failing tests for deduplication, conflicting versions, missing required tokens, optional events, and deterministic ordering.
- [ ] Run `venv/bin/pytest tests/trace_cag/test_dependency_trace.py -q`; expect failures because the module does not exist.
- [ ] Implement immutable `DependencyEvent` and `compile_dependency_trace(events)` with no Redis or graph dependency.
- [ ] Add `dependency_events` to `TraceCAGState` and a typed dependency record to `CacheAdmissibilityCertificate`.
- [ ] Run the focused test; expect all cases to pass.
- [ ] Run `venv/bin/pytest tests/trace_cag/test_dependency_trace.py tests/trace_cag/test_l1_state_cache_certificate.py -q`.
- [ ] Commit with `feat(trace-cag): compile explicit dependency traces`.

### Task 3: Upgrade certificate schema and cache admission

**Files:**
- Modify: `api/services/trace_cag/state.py`
- Modify: `api/services/trace_cag/cache_utils.py`
- Modify: `api/services/trace_cag/l1_state_cache.py`
- Modify: `tests/trace_cag/test_l1_state_cache_certificate.py`
- Create: `tests/trace_cag/test_cache_certificate_v3.py`

- [ ] Write failing tests requiring schema v3 dependency snapshots, factual hash, provenance hash, and patchable slots.
- [ ] Add a failing test proving an incomplete required trace prevents cache write rather than merely rejecting later reuse.
- [ ] Increment the certificate schema version and make legacy certificates fail closed without crashing.
- [ ] Compile dependency events in `_build_admissibility_certificate`; return a non-cacheable result on invalid traces.
- [ ] Compute deterministic factual/provenance projection hashes with existing JSON/hash utilities; do not add a dependency.
- [ ] Run focused certificate tests and then existing cache-gate tests.
- [ ] Commit with `feat(trace-cag): store dependency-complete certificates`.

## Chunk 2: One router, one score

### Task 4: Unify SCAR in the production module

**Files:**
- Modify: `api/services/trace_cag/l1_state_cache.py`
- Modify: `api/services/trace_cag/cache_utils.py`
- Modify: `service/tracecag_service/core/scar_l1.py`
- Modify: `model-development/tracecag_benchmark/tracecag/scar_l1.py`
- Create: `tests/trace_cag/test_scar_parity.py`

- [ ] Write table-driven tests for intent, concept, relation, evidence, and staleness deltas with frozen expected risk values.
- [ ] Add a test proving a hard-gate failure remains `full` even when computed soft risk is zero.
- [ ] Implement one pure production score using named frozen weights that sum to 1.0.
- [ ] Remove `_compute_reuse_risk` duplication from `cache_utils.py`; call the canonical decision result only.
- [ ] Replace duplicate service/benchmark implementations with imports or thin compatibility re-exports; do not maintain copied formulas.
- [ ] Run `venv/bin/pytest tests/trace_cag/test_scar_parity.py tests/trace_cag/test_l1_state_cache.py tests/trace_cag/test_l1_drift_probe_decisions.py -q`.
- [ ] Commit with `refactor(trace-cag): use one certificate-gated SCAR`.

### Task 5: Instrument active resolvers with explicit events

**Files:**
- Modify: active learner-state, KG, policy/prompt, evidence/source resolver modules discovered by `rg -n "learner_profile|kg_version|policy_version|evidence_hash|source_version" api/services/trace_cag`.
- Modify: `api/services/trace_cag/state.py`
- Create: `tests/trace_cag/test_resolver_dependencies.py`

- [ ] Enumerate the exact active resolver functions and their canonical dependency keys before editing.
- [ ] Write one failing test per dependency kind showing the resolver emits key, kind, version, and provenance.
- [ ] Add the smallest explicit append at each real read boundary; do not wrap unrelated stores or introduce automatic instrumentation.
- [ ] Add an integration test compiling a complete production trace from a representative request.
- [ ] Run `venv/bin/pytest tests/trace_cag/test_resolver_dependencies.py -q` and the node-level TRACE-CAG tests.
- [ ] Commit with `feat(trace-cag): record resolver dependency events`.

## Chunk 3: Mutation safety

### Task 6: Add reverse dependency invalidation

**Files:**
- Create: `api/services/trace_cag/invalidation.py`
- Modify: `api/services/trace_cag/cache_utils.py`
- Create: `tests/trace_cag/test_reverse_invalidation.py`

- [ ] Write failing tests with the existing fake/in-process cache for edge registration, targeted invalidation, unrelated survival, and edge cleanup.
- [ ] Implement dependency-key-to-artifact sets using existing Redis client helpers and an in-process test fallback.
- [ ] Register reverse edges only after a successful artifact write.
- [ ] Remove reverse edges on explicit deletion/invalidation; TTL cleanup may be lazy and documented as such.
- [ ] Retain bucket-version invalidation as the coarse fallback when precise keys are unavailable.
- [ ] Run focused invalidation tests and cache tests.
- [ ] Commit with `feat(trace-cag): invalidate artifacts by dependency`.

### Task 7: Connect mutation writers

**Files:**
- Modify: actual learner-state/KG/policy mutation functions found with `rg -n "update|mutat|increment|epoch|version" api/services backend-service`.
- Modify: `api/services/trace_cag/invalidation.py`
- Create: `tests/trace_cag/test_mutation_invalidation.py`

- [ ] For each claimed dependency kind, identify the single shared mutation boundary; do not patch individual callers.
- [ ] Add failing tests asserting token increment occurs before invalidation.
- [ ] Call targeted invalidation from those shared mutation boundaries.
- [ ] Add a test proving an unrelated mutation leaves the artifact available.
- [ ] Run focused tests plus learner-state tests.
- [ ] Commit with `feat(trace-cag): invalidate cache on versioned mutation`.

### Task 8: Add optimistic pre-serve recheck

**Files:**
- Modify: `api/services/trace_cag/dependencies.py`
- Modify: `api/services/trace_cag/cache_utils.py`
- Create: `tests/trace_cag/test_optimistic_recheck.py`

- [ ] Write an async race test where the token changes after initial validation but before L0 return.
- [ ] Add the same race test for L1 reuse and patch.
- [ ] Implement a token-reader callback and `recheck_dependency_snapshot` returning structured failure reasons.
- [ ] Call recheck at the final common return boundary for reuse/patch; on mismatch continue to L2 with `snapshot_changed_before_serve` audit metadata.
- [ ] Test missing/unavailable tokens also fail closed.
- [ ] Run focused race tests repeatedly, for example `venv/bin/pytest tests/trace_cag/test_optimistic_recheck.py -q --count=20` when `pytest-repeat` is installed; otherwise use a shell loop without adding a dependency.
- [ ] Commit with `feat(trace-cag): recheck dependency tokens before reuse`.

### Task 9: Enforce typed patch postconditions

**Files:**
- Modify: `api/services/trace_cag/cache_utils.py`
- Modify: `api/services/trace_cag/state.py`
- Modify: `tests/trace_cag/test_cache_gate_l1.py`
- Create: `tests/trace_cag/test_patch_contract.py`

- [ ] Write failing tests for an allowed presentation-only patch and rejected factual/provenance modifications.
- [ ] Replace free-form patch permission with declared slot checks and pre/post projection hash validation.
- [ ] Ensure failed patch verification falls through to L2 rather than serving the unpatched candidate.
- [ ] Run patch, certificate, and cache-gate tests.
- [ ] Commit with `feat(trace-cag): enforce patch factual invariants`.

## Chunk 4: Research evaluation

### Task 10: Add controller-isolating benchmark modes

**Files:**
- Modify: `model-development/benchmark/tracecag_bench/catalog.py`
- Modify: `model-development/benchmark/tracecag_bench/runtime/ai_service.py`
- Modify: `tests/benchmark/test_runtime_protocols.py`
- Create: `tests/benchmark/test_mode_isolation.py`

- [ ] Define modes for `l2_only`, `exact_cache`, `l0_l1_no_certificate`, `l0_l1_certificate`, and `tracecag_full` while holding retriever, generator, prompt, and evidence budget fixed.
- [ ] Write tests asserting each ablation changes only its named controller feature.
- [ ] Route every mode through the production certificate/SCAR implementation.
- [ ] Keep `hipporag_proxy` explicitly marked proxy and outside controller-effect claims.
- [ ] Run benchmark configuration/runtime tests.
- [ ] Commit with `test(benchmark): isolate trace-cag controller effects`.

### Task 11: Add deterministic route and drift gates

**Files:**
- Modify: `model-development/benchmark/tracecag_bench/protocols/drift_safety.py`
- Modify: `model-development/benchmark/tracecag_bench/metrics/safety.py`
- Create: `tests/benchmark/test_drift_route_coverage.py`
- Modify: `model-development/benchmark/daily_benchmark_manifest.json`

- [ ] Add provider-free fixtures for safe paraphrase, relevant drift, irrelevant drift, patchable delta, factual delta, and validate/serve race.
- [ ] Fail preflight unless L1 reuse, L1 patch, safe rejection, and mutation-recheck paths are each observed.
- [ ] Add unsafe-serving rate, safe-reuse precision, admissible recall, patch precision/recall, route accuracy, and recheck/invalidation overhead.
- [ ] Add Wilson intervals and paired cluster/item resampling using existing metric utilities or Python stdlib; do not add a statistics framework.
- [ ] Run `venv/bin/pytest tests/benchmark/test_drift_route_coverage.py tests/benchmark/test_metrics.py -q`.
- [ ] Commit with `feat(benchmark): gate trace-cag drift coverage`.

### Task 12: Run validation and frozen benchmarks

**Files:**
- Update generated artifacts only under `model-development/reports/benchmarks/`.
- Do not edit source or thresholds after a final stage starts under one protocol ID.

- [ ] Run the full focused suite: `venv/bin/pytest tests/trace_cag tests/benchmark model-development/tracecag_benchmark/tests -q`.
- [ ] Start/check Redis using the existing benchmark Docker workflow; do not start unrelated services.
- [ ] Run provider-free deterministic drift validation and archive its JSON/log/hash.
- [ ] Run the fixed paid preflight and stop if provider/model, KG isolation, route coverage, or artifact validation fails.
- [ ] Freeze clean implementation SHA, dependency lock hash, prompt hashes, dataset hashes, and protocol ID.
- [ ] Run the frozen ablations and final datasets with `venv/bin/python model-development/benchmark/run_daily_benchmark.py --day N`; use `--resume` only when protocol hashes match.
- [ ] Compute paired intervals/tests and preserve raw observations; never assemble per-cell “best” values from incompatible runs.
- [ ] Record a claim–evidence matrix identifying the exact artifact behind every numeric claim.

## Chunk 5: Paper alignment and release gate

### Task 13: Rewrite claims, algorithm, and positioning

**Files:**
- Modify: `model-development/scripts/build_icta_paper.py`
- Modify: paper source used by the builder, if separate.
- Generate: `model-development/pdf/TRACE-CAG_ICTA_2026_generated_preview.docm`
- Preserve: `model-development/pdf/TRACE-CAG_ICTA_2026_camera_ready_8pages_v5.docm`

- [ ] Replace “calibrated” with “expert-weighted” unless calibration artifacts now exist.
- [ ] State the single unified SCAR feature set and frozen weights.
- [ ] Make Algorithm 1 guard an empty candidate set, separate cache admission from L2 return, and include optimistic recheck.
- [ ] Describe explicit dependency capture and actual reverse-index behavior, with no stronger concurrency claim than tested.
- [ ] Describe Selective IRCoT as benchmark L2 and its actual source-anchor/bridge-document contract.
- [ ] Add GroundedCache, FreshCache, Krites, RAGCache, and TurboRAG positioning; avoid “first safe router” or “first hierarchical cache”.
- [ ] Report effect sizes/intervals and call point estimates non-significant when tests do not establish superiority.
- [ ] Generate preview only; compare all claims against the matrix before replacing the manually edited master.

### Task 14: Final document and submission verification

**Files:**
- Final candidate: `model-development/pdf/TRACE-CAG_ICTA_2026_camera_ready_8pages_v5.docm`
- Create: `model-development/reports/benchmarks/final/tracecag_claim_evidence_matrix.md`
- Create: `model-development/reports/benchmarks/final/submission_checklist.md`

- [ ] Confirm the exact conference identity, official template, page rule, anonymity rule, and accepted upload format from its CFP.
- [ ] If double blind, remove authors, affiliations, acknowledgments, self-identifying text, and identifying document metadata from the submission copy.
- [ ] Open/render the DOCM with Microsoft Word or a compatible renderer; verify exactly eight pages including references.
- [ ] Inspect every page at 100% for clipped equations, overflowing tables, figure arrows, caption wrapping, font substitution, and orphan headings.
- [ ] Verify macros/styles remain intact and all fonts are embedded in the exported PDF.
- [ ] Recompute artifact hashes and confirm every table/figure value maps to the frozen run.
- [ ] Run the full test suite relevant to changed backend code, then request code review per repository policy.
- [ ] Mark the paper submission-ready only when all scientific, implementation, benchmark, and document gates pass.

## Stop conditions

- Stop final evaluation if L1/patch routes are not exercised in preflight.
- Stop paper generation if production and benchmark SCAR parity fails.
- Stop reuse on any missing dependency token or recheck error.
- Stop submission if a central claim lacks a test and frozen artifact.
- Start a new protocol ID after any source, prompt, threshold, dataset, KG, or provider-policy change.
