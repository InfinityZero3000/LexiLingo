# AI Service Production E2E Design

**Date:** 2026-07-26

## Goal

Provide one production-like Docker Compose path that verifies LexiLingo's AI service end to end against real MongoDB, Redis, and Groq, measures actionable latency, and produces a safe server deployment handoff.

## Scope

This delivery covers the AI service request path, its MongoDB and Redis dependencies, the existing seven-key Groq pool, container readiness, a reproducible E2E runner, latency reporting, focused bottleneck remediation, and server operations documentation.

It does not deploy to the server because server access is not available. It does not promise that no future technical debt or production bottleneck can exist; completion means no unresolved critical/high finding in the exercised path and no measured latency gate violation at the defined light-load profile.

## Architecture

Use the existing Docker Compose deployment rather than introduce another orchestration layer. MongoDB and Redis run as real containers. The AI service uses the same FastAPI lifespan and router wiring as production and calls Groq through the existing `GroqKeyPool`.

A small E2E runner uses existing Python dependencies and public service contracts. It validates configuration without exposing secrets, waits for readiness, exercises authenticated provider-backed requests, verifies persistence and cache behavior, samples all seven key slots through non-secret fingerprints or pool telemetry, and emits a machine-readable JSON report.

The benchmark runs cold, warm, and seven-request concurrent slices. It records p50, p95, p99, time to first token when streaming is available, throughput, cache route, provider classification, and error rate. Performance changes are allowed only when a failing measurement identifies the bottleneck.

## Configuration and Secrets

Local `.env` receives a generated random `MONGO_EXPRESS_PASSWORD`; it remains ignored by Git. Examples and deployment documentation list names and generation commands, never real values.

Required server secrets:

- `GROQ_API_KEYS`: exactly seven comma-separated Groq keys.
- `SECRET_KEY`: shared JWT secret, at least 32 random characters, matching the backend.
- `AI_ADMIN_API_KEY`: shared internal API secret, matching the backend.
- `MONGO_EXPRESS_PASSWORD`: random Mongo Express password.
- `MONGO_EXPRESS_USER`: optional non-default username.
- Provider or monitoring secrets already required by enabled production features, such as `SENTRY_DSN`, remain optional unless the feature is enabled.

The E2E output must not contain raw keys, bearer tokens, JWT secrets, admin keys, connection strings with credentials, or request content that could expose user data.

## Data Flow

1. Compose validates required variables and starts MongoDB and Redis.
2. Their health checks pass before the AI service starts.
3. FastAPI lifespan connects MongoDB, creates safe indexes, connects Redis, builds the seven-key Groq pool, and initializes enabled runtimes.
4. The E2E runner waits for container and HTTP readiness.
5. It sends authenticated requests through the real API boundary.
6. The request reaches the existing orchestration/TraceCAG path and Groq provider.
7. The runner verifies response shape, provider provenance, persistence, warm-cache behavior, and safe key-pool observations.
8. The runner writes a timestamped JSON report and returns non-zero if correctness, security, or latency gates fail.

## E2E Scenarios

The minimum suite verifies:

- Compose configuration resolves with required secrets.
- MongoDB and Redis health checks pass.
- AI service startup and health/readiness pass.
- Exactly seven Groq keys are recognized without logging values.
- Authenticated chat or TraceCAG request produces a real Groq-backed response.
- The resulting session/interaction is readable through its supported API contract.
- Repeating an eligible request exercises the warm/cache path without changing correctness.
- Seven concurrent provider requests complete without duplicate admission, secret leakage, or unbounded failure.
- A simulated unavailable/exhausted provider produces the documented bounded error or fallback, not a hang.
- Service restart preserves durable state and does not corrupt cache/index initialization.

Optional heavy STT/TTS model tests remain separate because model provisioning and hardware vary by server. Their readiness is reported explicitly rather than silently skipped.

## Performance Gates

The initial light-load gates are:

- Health endpoint p95: at most 500 ms.
- Warm/cache-eligible chat p95: at most 2 seconds.
- Cold Groq-backed chat p95: at most 12 seconds.
- Seven-request concurrent error rate: below 1%.
- Every outbound provider request has a finite timeout; the E2E run itself has a finite deadline.

If server measurements show these budgets are unrealistic for the selected Groq model or network, adjust them only with a committed report and rationale. Do not hide failures by silently relaxing validation.

## Technical-Debt and Bottleneck Review

Review only the exercised production path and its direct dependencies. Prioritize:

- duplicated provider clients or bypasses around `GroqKeyPool`;
- blocking work on the FastAPI event loop;
- unbounded queues, buffers, retries, sessions, or caches;
- missing timeouts and cancellation handling;
- repeated model/database initialization;
- secret-bearing logs or reports;
- health checks that trigger expensive model work;
- cache correctness and invalidation gaps affecting measured requests;
- container startup ordering, resource limits, and graceful shutdown.

Findings are ranked critical/high/medium/low with evidence. Only critical/high issues blocking the E2E or latency gates are fixed in this delivery. Lower-severity findings become an explicit debt ledger rather than speculative refactors.

## Error Handling and Rollback

Configuration errors fail before traffic is accepted. Dependency readiness is bounded by timeouts. Provider quota/rate-limit failures produce structured diagnostics without identifying a key. Reports are still written on failure.

Deployment uses a pinned Git commit. Rollback checks out the previous known-good commit and recreates only the AI service container; MongoDB and Redis volumes are retained. No destructive database reset is part of E2E or rollback.

## Verification

Completion requires:

- focused tests for configuration validation, report redaction, statistics, and gate failures;
- the existing AI service test suite;
- Python compilation and `git diff --check`;
- Docker Compose config validation;
- a real-provider E2E run with seven configured keys;
- a generated latency report;
- security, test, technical-debt, and final code reviews;
- server runbook with configuration, deploy, smoke, benchmark, observability, and rollback commands.

## Deliverables

- Minimal Compose/env corrections.
- E2E/benchmark runner and tests.
- Timestamped report schema and safe sample output.
- Focused performance fixes supported by measurements, if needed.
- Technical-debt ledger for deferred non-blocking findings.
- Server deployment and rollback runbook.
