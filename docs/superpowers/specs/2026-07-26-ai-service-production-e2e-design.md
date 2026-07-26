# AI Service Production E2E Design

**Date:** 2026-07-26

## Goal

Provide one production-like Docker Compose path that verifies LexiLingo's AI service end to end against real MongoDB, Redis, and Groq, measures actionable latency, and produces a safe server deployment handoff.

## Scope

This delivery covers the AI service request path, its MongoDB and Redis dependencies, the existing seven-key Groq pool, container readiness, a reproducible E2E runner, latency reporting, focused bottleneck remediation, and server operations documentation.

It does not deploy to the server because server access is not available. It does not promise that no future technical debt or production bottleneck can exist; completion means no unresolved critical/high finding in the exercised path and no measured latency gate violation at the defined light-load profile.

## Architecture

Use `ai-service/docker-compose.yml` as the isolated E2E stack with Compose project name `lexilingo-ai-e2e`; the canonical commands are `docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml config` and `docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml up -d --build mongodb redis ai-service`. The file will use `Dockerfile.prod`, no reload/source bind mount, and the same FastAPI lifespan and router wiring as the root production Compose. Mongo Express is excluded by default and starts only with `--profile admin`.

A small host-side E2E runner uses existing Python dependencies and public service contracts. It validates configuration without exposing secrets, waits for readiness, exercises authenticated provider-backed requests, verifies persistence and cache behavior, observes all seven key slots only through safe slot-ID telemetry, and emits a machine-readable JSON report.

The benchmark runs cold, warm, and seven-request concurrent slices. It records p50, p95, p99, time to first token when streaming is available, throughput, cache route, provider classification, and error rate. Performance changes are allowed only when a failing measurement identifies the bottleneck.

## Configuration and Secrets

Local `ai-service/.env` receives a generated random `MONGO_EXPRESS_PASSWORD`; it remains ignored by Git and is written without shell tracing. Secret files use mode `0600`. Examples and deployment documentation list names and generation commands, never real values.

Required server secrets:

- `GROQ_API_KEYS`: exactly seven comma-separated Groq keys.
- `SECRET_KEY`: shared JWT secret, at least 32 random characters, matching the backend.
- `AI_ADMIN_API_KEY`: shared internal API secret, matching the backend.
- `MONGO_EXPRESS_PASSWORD`: random Mongo Express password, required only when the optional admin profile is started.
- `MONGO_EXPRESS_USER`: optional non-default username.
- Provider or monitoring secrets already required by enabled production features, such as `SENTRY_DSN`, remain optional unless the feature is enabled.

The preflight trims comma-separated Groq values and rejects blanks, duplicates, or a usable count other than exactly seven. Reports expose only `configured_key_count` and zero-based slot IDs; they never hash or fingerprint key material. The E2E output must not contain raw keys, bearer tokens, JWT secrets, admin keys, connection strings with credentials, provider response bodies on error, or request content that could expose user data.

MongoDB is not published to the host and is reachable only on the Compose network. Redis requires `REDIS_PASSWORD` and, when a host diagnostic binding is enabled, binds only to `127.0.0.1`. Mongo Express binds only to `127.0.0.1`, uses basic authentication, and is not a production dependency. The root production stack does not start Mongo Express, so its password is not required on a server that runs only root `docker-compose.yml`.

## Data Flow

1. Compose validates required variables and starts MongoDB and Redis.
2. Their health checks pass before the AI service starts.
3. FastAPI lifespan connects MongoDB, creates safe indexes, connects Redis, builds the seven-key Groq pool, and initializes enabled runtimes.
4. The isolated E2E stack binds the AI API only to `127.0.0.1:8001`; the host runner waits at most 180 seconds for container health and uses direct `httpx` calls so process startup does not contaminate latency measurements. The root production stack remains unexposed behind its gateway.
5. It creates a short-lived HS256 access JWT locally from `SECRET_KEY` with issuer `lexilingo-backend`, audience `lexilingo-services`, subject `e2e-<run-id>`, claim `type: "access"`, and a five-minute expiry. It creates a session with `POST /api/v1/chat/sessions`, then calls `POST /api/v1/chat/messages`.
6. The request reaches the existing orchestration/TraceCAG path and Groq provider.
7. The runner verifies response shape, provider provenance, persistence, warm-cache behavior, and safe key-pool observations.
8. The runner writes a timestamped JSON report and returns non-zero if correctness, security, or latency gates fail.

## E2E Scenarios

The minimum suite verifies:

- Compose configuration resolves with required secrets.
- MongoDB and Redis health checks pass.
- AI service startup and health/readiness pass.
- Exactly seven Groq keys are recognized without logging values.
- `POST /api/v1/chat/messages` produces a non-empty response whose metadata names a Groq model and TraceCAG path; fixed safe fallback text is a failure.
- The session and both user/assistant messages are readable with `GET /api/v1/chat/sessions/{session_id}/messages` using the same JWT.
- A repeated deterministic request exercises cache reuse, proven by response route metadata rather than latency alone, without changing the normalized answer contract.
- Seven unique nonce-bearing, non-cacheable prompts are released concurrently. Each must cause a provider acquisition, and structured pool telemetry must contain every safe slot ID `0..6` once before any slot repeats. Telemetry contains no key-derived value.
- Provider exhaustion is tested offline through the existing key-pool injection seam with fake limiters; it never submits invalid requests or burns real-key quota. The operation must return no available key within one second. HTTP timeout behavior uses an injected fake provider in tests and must return the documented 504 within the route deadline.
- `docker compose ... up -d --force-recreate ai-service` recreates only the AI container while retaining named MongoDB/Redis volumes. The previously created session remains readable after readiness returns within 180 seconds. Redis cache survival is informational because Redis persistence/restart is not part of this check. Cleanup removes only E2E documents identified by `e2e-<run-id>` and generated reports older than the retention window; it never removes volumes.

Optional heavy STT/TTS model tests remain separate because model provisioning and hardware vary by server. Their readiness is reported explicitly rather than silently skipped.

## Performance Gates

The runner records Python/platform, CPU count, memory, container image IDs/resource limits, Groq model, Git commit, UTC time, and network-facing base URL. It uses `time.perf_counter_ns`, a 60-second per-request timeout, and a 20-minute run deadline. Percentiles use the nearest-rank method and always include sample count and method in the report.

After five unmeasured warm-up requests, the initial light-load gates are:

- Health endpoint p95 over 100 sequential samples: at most 500 ms.
- Warm/cache-eligible chat p95 over 30 samples: at most 2 seconds.
- Cold Groq-backed chat p95 over 14 unique samples, reported as a small-sample operational percentile: at most 12 seconds.
- Concurrent slice: five batches of seven unique requests; zero failures across all 35 requests. Throughput is successful responses divided by wall-clock time from the first release until the last completion.
- Streaming TTFT is measured separately on `/api/v1/lexi/stream`: request bytes flushed to first non-empty SSE data event, over 14 samples. It is reported but does not block this delivery until a baseline is captured.
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

Findings are ranked critical/high/medium/low with evidence. Every critical/high security, correctness, reliability, or measured-performance finding in the exercised path blocks completion and must be fixed or explicitly rejected by the user. Lower-severity findings become an explicit debt ledger rather than speculative refactors.

## Error Handling and Rollback

Configuration errors fail before traffic is accepted. Dependency readiness is bounded by timeouts. Provider quota/rate-limit failures produce structured diagnostics containing only slot ID and error class. Reports are still written on failure.

The host-side runner writes reports directly to `ai-service/reports/e2e/<UTC-run-id>.json`; reports therefore survive container recreation and need no container mount. They are retained for 30 days by bounded cleanup. The schema contains run identity, environment metadata, redacted configuration counts, scenario results, latency samples/aggregates, safe slot IDs, gates, and findings. Before writing and again after serialization, a scanner rejects configured secret values, authorization headers, JWTs, credential-bearing URLs, prompt bodies, provider bodies, and common key prefixes. Unit tests cover success and exception/error serialization.

Deployment uses a reviewed, pinned Git commit. Root acceptance is: `git fetch`, `git checkout <commit>`, create `.env.production` and `.env.production.secrets` with mode `0600`, validate root Compose, build/start dependencies and `ai-service`, wait for health, run gateway `/health` smoke, and inspect bounded logs and observability. Real-provider smoke, benchmark, and host-side JSON report retrieval run separately on the project-scoped isolated loopback stack. Mongo index creation remains the existing idempotent lifespan operation; no migration/reset command is added. Rollback selects the previously recorded commit, checks it out, rebuilds/recreates only root `ai-service`, retains MongoDB/Redis volumes, and verifies gateway health; durable-session restart verification belongs to the isolated E2E stack. No destructive database reset is part of E2E or rollback.

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
