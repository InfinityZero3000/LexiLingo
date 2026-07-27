# LexiLingo System Completion Roadmap

## Current assessment

The repository has the main product surfaces in place: Flutter client, FastAPI backend, AI/TRACE-CAG service, PostgreSQL learner state, Redis, Kuzu knowledge data, benchmark runners, and Python-rendered figures. The main risk is not missing functionality; it is integration drift and uncommitted work across several parallel changes.

Current verified signals:

- Docker Compose files parse, but the development stack is not currently running.
- Flutter analysis passes and focused UI tests pass.
- Focused TRACE-CAG/AI tests pass (65 tests).
- Focused learner-state backend tests pass (28 tests).
- Public benchmark results still contain legacy/smoke suites and pending larger runs; they must not be combined.

Main risks:

1. Working-tree changes are mixed across unrelated features and cannot yet form a reproducible release.
2. Learner state crosses PostgreSQL, outbox, AI overlay, Redis/cache, and Kuzu; failure/replay behavior needs an end-to-end runtime test.
3. TRACE-CAG has dependency-aware code, but production and benchmark semantics must remain identical.
4. Benchmark evidence is not yet sufficient for broad safety or deployment claims.
5. The tactile theme change currently removes the border from all learner `IconButton`s, not only Back buttons.

## Phase 0 — Freeze and isolate (P0)

- Create a clean release branch from the tagged commits.
- Keep documentation, paper, benchmark outputs, datasets, and runtime databases outside production commits.
- Classify remaining changes into: learner-state, TRACE-CAG, benchmark, Flutter UI, or unrelated.
- Require every later phase to produce a small commit and a passing focused test.

Exit criteria: clean release branch, no generated data or secrets tracked, and a written change manifest.

## Phase 1 — Runtime health and local stack (P0)

- Start `docker-compose.dev.yml` with PostgreSQL, Redis, Redis-AI, backend, and AI service.
- Add/verify health checks for HTTP readiness, PostgreSQL migration state, Redis ping, and AI dependency readiness.
- Run migrations from a clean database.
- Verify backend → AI service → Redis → PostgreSQL request flow with one authenticated learner.
- Verify logs include correlation/request IDs and never include raw tokens, user identifiers, or answer payloads unnecessarily.
- Add a single smoke command that exits non-zero on any failed dependency.

Exit criteria: all Compose health checks are `healthy` for 10 consecutive minutes, one learner request succeeds, one cache miss and one cache hit are observable, and restart recovery passes.

## Phase 2 — Learner-state correctness (P0)

- Test observation ingestion, outbox claim, retry, dead-letter, idempotency, and chronological ordering.
- Run PostgreSQL integration tests with the Docker Postgres instance; do not treat sandbox-blocked tests as passed.
- Verify PostgreSQL remains source of truth and Kuzu receives only the intended projection.
- Run export/import and reconciliation on a fixture with duplicate, delayed, and failed events.
- Add metrics for pending rows, retry count, dead letters, applied lag, duplicate applications, and PostgreSQL/Kuzu mismatch.
- Execute rollback/replay drill before enabling production traffic.

Exit criteria: zero duplicate applications, zero lost observations in the normal-path fixture, deterministic replay, and reconciliation report with zero unexplained mismatches.

## Phase 3 — TRACE-CAG contract and cache safety (P0)

- Make certificate schema v2, dependency declaration, admissibility, risk, and routing a single shared implementation.
- Enforce fail-closed behavior for missing mandatory fields at L0 and L1.
- Add atomic read → validate → version recheck immediately before serving a cached answer.
- Verify bounded patch cannot change factual/evidence-dependent fields.
- Test invalidation for profile, policy, KG, evidence, source, freshness, and relation changes.
- Ensure cache keys are user-scoped where needed and never contain raw personal data.
- Change the tactile icon style so only `AppBackButton` is borderless; preserve the visual treatment of unrelated icon controls.

Exit criteria: production and benchmark contract fixtures return identical route/reason pairs, stale certificates cannot be served, and all focused contract tests pass.

## Phase 4 — Fair benchmark pipeline (P0)

- Use clean DriftBench-v2 24 as the only smoke result.
- Keep legacy 122 in a separately labeled compatibility appendix, or remove it from the main paper.
- Run the seven 24-case modes with dataset/config/git/seed provenance.
- Validate no answer preload, reference leakage, cache contamination, provider fallback, or cross-mode state leakage.
- Run one dataset per day using preflight n=5, resume support, raw output, summary, checksum, cost, and validation status.
- Run HotpotQA 64, 2Wiki 64, Query Clusters 32, MuSiQue 500, DriftBench-240, baselines, and threshold sensitivity only in that order.
- Report Wilson intervals, drift-type breakdown, unsafe acceptance, admissible recall, patch recall, route accuracy, and threshold sensitivity.

Exit criteria: every paper-ready metric is generated from a passed run; missing metrics remain `Pending`, never inferred.

## Phase 5 — Production observability and cost control (P1)

- Add dashboards for route counts, cache hit/miss, hard rejects, patches, full generation, latency by route, token cost, provider errors, learner-state lag, and dead letters.
- Add alerts for unsafe acceptance, certificate mismatch spikes, cache invalidation storms, provider quota errors, and queue growth.
- Bound retries, timeouts, concurrency, and prompt size.
- Use exact-cache short circuits before LLM calls and keep embedding model loaded once per process/run.
- Add a canary mode and a kill switch that forces full generation.

Exit criteria: a 24-hour local soak test has no unbounded queue/retry loop, no crash restart, error rate below 1%, p95 route latency within the agreed SLO, and memory growth below 10% after warm-up.

## Phase 6 — Paper and release evidence (P1)

- Rewrite the novelty claim around typed application-state admissibility contracts and bounded patching.
- Compare GroundedCache, FreshCache, vCache, ContextCache, and CacheRAG without overstating equivalence.
- Use only clean 24-case results until larger runs pass.
- Mark DriftBench-240, embedding baseline, version-aware baseline, and public-QA results as pending until validated.
- Include worked examples, formal equations, confidence intervals, threshold sensitivity, and limitations.
- Produce anonymous `.docm` only after the final result tables and metadata audit are complete.

Exit criteria: paper claims match code and passed evidence; no legacy number is mixed into main results; anonymous submission artifact renders correctly.

## Phase 7 — Product expansion (P2)

- Add admin views for learner-state consistency, cache decisions, and benchmark provenance.
- Add multi-tenant isolation and per-tenant policy/version scopes.
- Add backup/restore drills for PostgreSQL, Redis, and Kuzu projection data.
- Add load testing for concurrent learners and long sessions.
- Only then evaluate provider/model upgrades or architectural refactors.

Exit criteria: admin views show live consistency and route data, tenant-isolation integration tests pass, backup/restore meets the documented RPO/RTO, and the concurrent-learner load test meets the agreed p95 latency/error SLO without observation loss.

## Recommended execution order

`Freeze branch → local health stack → learner-state integration → shared TRACE-CAG verifier → clean 24 benchmark → daily public datasets → observability/soak → paper finalization → product expansion`.

Do not start the 500-sample MuSiQue run or make an ICTA claim before Phases 0–4 pass.
