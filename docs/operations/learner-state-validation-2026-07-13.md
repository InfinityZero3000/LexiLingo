# Learner-state validation — 2026-07-13

## Automated evidence

- AI focused learner-state, spool, cache, streaming and pipeline suites: 57 tests passed in the broad focused run; subsequent changed-path run: 43 passed.
- TRACE-CAG pipeline integration: 6 passed in 4.04 seconds. Tests are hermetic and do not contact Ollama, Hugging Face, document intelligence, Redis, Kuzu or external retrieval.
- Backend learner-state schema, route, algorithm, outbox, migration and import focused suites: 35 passed.
- Backend full suite: 1,155 passed; 190 setup errors because the local PostgreSQL test database was unavailable. No learner-state focused failure occurred.
- Docker Compose configuration validation passed with `docker compose -f docker-compose.dev.yml config --quiet`.
- Ruff passed for all changed learner-state Python modules and load scripts.
- Security re-review and code review approved the implemented paths with no remaining code blocker.
- Real PostgreSQL outbox execution on PostgreSQL 16 passed: 2/2 tests. Two
  workers applied distinct events for one user/concept exactly once in
  deterministic order (`attempt_count=2`, `state_epoch=2`), and an expired
  processing lease was reclaimed/replayed without a duplicate state update.
- The Locust harness now uses a one-token/one-user JSONL identity pool and
  creates authenticated sessions before sending messages. Harness tests: 6
  passed. A one-user live probe created its session successfully with correct
  JWT scoping; the previous shared-token/random-user and missing-session 403/404
  failures are fixed. The identity pool rejects duplicate users/tokens, a
  session-specific canary is seeded before all users issue shared repeated
  prompts. The identical isolation query must return the current user's canary
  and must never return another user's canary. Every HTTP call has a 60-second
  client deadline, and the run exits non-zero if any spawned user does not
  complete isolation initialization. It also rejects group/world-readable token
  files and shared identities for multi-user runs; the 18 focused harness tests
  pass.
- The live probe uncovered a query-string credential leak risk. Gemini keys now
  use the `x-goog-api-key` header at every TRACE-CAG call site and transport INFO
  logs are disabled; security re-review reports no remaining blocker.
- Fresh service startup no longer blocks the event loop while Kuzu initializes:
  `/health` returned in 68 ms during cold initialization. Concurrent cold-start
  tests confirm one shared orchestrator initialization. Kuzu import now uses
  bounded `UNWIND` batches; a real 5,223-concept/15,633-edge sync completed in
  approximately 6 seconds (the isolated 4,040-concept/14,640-edge loader phase
  completed in 5.936 seconds).
- Local Qwen3 requests now receive `/no_think`; a direct warm Ollama probe
  completed in 0.86 seconds. The non-streaming chat route now imposes a
  30-second primary deadline, a 15-second degraded-retry deadline, and a
  50-second whole-request deadline, preventing cold initialization, DB/cache, or
  model/provider stalls from holding request capacity indefinitely. Public
  fallback metadata contains only fixed exception type names, never raw errors.
- Orchestrator initialization is a cancellation-safe single-flight task. Kuzu
  startup runs off the event loop and holds a nonblocking filesystem lock for
  the full process lifetime, enforcing one worker per embedded snapshot (or a
  separate `KUZU_DB_PATH`). Failure and shutdown release the lock. KG edge batch
  counts are verified; incomplete edges do not persist a sync hash and are
  retried after missing concepts become available.
- Latest blocker-regression set: 38 tests passed with Ruff clean. Final security
  and code re-reviews report no remaining blocker.

## Execution gates not measured

The Docker daemon is now available. PostgreSQL concurrency has been measured,
but the following must still not be represented as passing:

- 100-user/5-minute and 1,000-user/15-minute Locust profiles;
- Redis/backend/Mongo dependency-failure stages;
- live `primary → read → off` rollback drill;
- measured p50/p95/p99, maximum safe concurrency, PostgreSQL connections, cache-hit rate, observation loss and divergence.

The staged load run is blocked by inference capacity, not learner-state storage.
The configured external providers returned Gemini `429` and Groq `401`. A local
1.7B Qwen model was then used to remove the credential dependency. The bounded
single-user probe produced: session creation 39 ms, seed 45.506 s (30-second
primary deadline plus 15-second retry), and isolation 83 ms. Isolation correctly
failed because the fallback response did not contain the user's canary; the run
exited non-zero with `learner-isolation-incomplete`. This is valid negative
evidence: even one user does not meet functional/latency gates on this local
inference stack, so running 100 or 1,000 users would only overload the model and
would not establish production capacity. Rotate the credential observed by the
pre-fix transport log and provide a load-test inference endpoint with production-
equivalent quotas before rerunning both stages.

The repository intentionally bootstraps a fresh database with SQLAlchemy
`create_all` followed by `alembic stamp head`; historical migrations are only
for incremental redeploys. The production entrypoint previously called the
bootstrap script through the wrong path and printed the credential-bearing
database URL. Both defects are fixed. On PostgreSQL 16, fresh `create_all`,
`stamp head`, no-op `upgrade head`, then learner-state `downgrade -1` and
`upgrade head` all passed. The entrypoint subprocess regression test also passes
and verifies URL redaction plus command ordering.

A full backend rerun reached 159 passed and exposed two stale cleanup mocks
after cleanup-lag/archive support was added. Both tests were corrected and now
pass; the long full-suite rerun was interrupted after 10 minutes, so this is not
recorded as a full-suite pass.

Production promotion remains prohibited until these rows are replaced with measured results from `ai-service/tests/load/README.md`. Code defaults and thresholds in the rollout document are safety targets, not capacity claims.
