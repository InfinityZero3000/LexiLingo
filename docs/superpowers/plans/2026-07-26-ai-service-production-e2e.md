# AI Service Production E2E Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a secure, reproducible production-like AI-service E2E path using MongoDB, Redis, and seven real Groq keys, with latency gates and a server deployment runbook.

**Architecture:** Harden the existing isolated AI-service Compose stack instead of adding orchestration. Add one stdlib-first host runner that validates secrets, drives the public authenticated API, records safe slot telemetry and latency, and writes redacted JSON reports; change production code only where tests or measurements prove a blocking defect.

**Tech Stack:** Docker Compose, FastAPI, MongoDB, Redis, Groq, Python stdlib, existing `httpx`/`python-jose`, pytest.

---

## Chunk 1: Secure runtime and deterministic validation

### Task 1: Harden the isolated Compose stack and environment contract

**Files:**
- Modify: `ai-service/docker-compose.yml`
- Modify: `ai-service/.env.example`
- Test: `ai-service/tests/test_container_hardening.py`

- [ ] Add failing parsed-Compose assertions for `build.dockerfile: Dockerfile.prod`, `ENVIRONMENT=production`, no reload/source bind mount, `GROQ_API_KEYS` and `GROQ_SLOT_TELEMETRY` propagation, Redis password in server command/healthcheck/client variables, no MongoDB host publication, loopback-only Redis/API publication, project-scoped container naming, and Mongo Express under the `admin` profile with loopback binding.
- [ ] Add subprocess tests proving default `compose config` succeeds without Mongo Express credentials, `--profile admin up` fails before starting Mongo Express without its password, and admin config/start validation succeeds when credentials are supplied. Avoid `${VAR:?}` on the inactive profile; validate the password in the admin container command/entrypoint.
- [ ] Run `cd ai-service && python3 -m pytest tests/test_container_hardening.py -q` and confirm failure.
- [ ] Make the minimum Compose/env changes satisfying those assertions; do not add another Compose file or dependency.
- [ ] Generate a local random `MONGO_EXPRESS_PASSWORD` in ignored `ai-service/.env` without displaying it and set file mode `0600`.
- [ ] Run the focused test and, from repository root, `docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml config`.
- [ ] Commit only Task 1 files.

### Task 2: Validate and instrument the seven-key pool safely

**Files:**
- Modify: `ai-service/api/core/groq_key_pool.py`
- Modify: `ai-service/tests/test_groq_key_pool.py`

- [ ] Add failing tests for whitespace trimming, blank/duplicate rejection in E2E strict mode, exact count seven, concurrency-safe round-robin selection, offline all-limiters-exhausted return within one second, and telemetry containing slot IDs but no key material.
- [ ] Run `cd ai-service && python3 -m pytest tests/test_groq_key_pool.py -q` and confirm failure.
- [ ] Reuse the existing pool and add only validation, an acquisition lock, and structured `groq_slot_acquired slot_id=<0..6>` logging guarded by `GROQ_SLOT_TELEMETRY=true`; preserve non-E2E compatibility. A new isolated service process resets the cursor, and the runner observes logs only since its recorded UTC start time.
- [ ] Run the focused test and commit Task 2 files.

## Chunk 2: E2E runner and evidence

### Task 3: Implement the redacted E2E/latency runner

**Files:**
- Create: `ai-service/scripts/e2e_ai_service.py`
- Create: `ai-service/tests/test_e2e_ai_service.py`
- Modify: `ai-service/.gitignore`

- [ ] Write failing unit tests for nearest-rank percentiles, exact-seven secret preflight, short-lived JWT claims, report schema, success/error redaction, latency gates, bounded report retention, E2E-document cleanup restricted to `e2e-<run-id>`, injected provider timeout mapping to HTTP 504, and non-zero failure result.
- [ ] Assert the report includes throughput, zero/observed error rate, cache route, provider class, SSE TTFT parsing, CPU/memory, image IDs/resource limits, model, commit, UTC timestamp, platform, and base URL.
- [ ] Run `cd ai-service && python3 -m pytest tests/test_e2e_ai_service.py -q` and confirm failure.
- [ ] Implement one host-side runner with a 20-minute deadline and 60-second request timeout. Use existing `httpx` and `python-jose`; do not add a framework.
- [ ] Implement `smoke` mode over loopback `http://127.0.0.1:8001`: wait for readiness, create JWT/session, send a unique Groq-backed chat, verify metadata and persisted messages, then optionally verify the same session after AI-container recreation.
- [ ] Implement cache validation using two fresh sessions with equivalent normalized input; require cache-route metadata and normalized answer parity so conversation history cannot alter the key.
- [ ] Implement `benchmark` mode: five warmups, 100 health samples, 30 warm-cache samples, 14 cold unique samples, five batches of seven unique concurrent samples, and 14 streaming TTFT samples; report nearest-rank p50/p95/p99, throughput/error rate, provider/cache classification, environment fields, and explicit sample counts.
- [ ] Implement safe slot observation by recording start UTC, running a newly recreated isolated AI container with telemetry enabled, submitting seven synchronized unique requests, then parsing `docker compose ... logs --since <start>`; require exact `0..6` before repetition.
- [ ] Implement cleanup through a bounded Mongo operation selecting only the exact E2E user/run ID and report files older than 30 days; never invoke volume deletion.
- [ ] Scan serialized success and failure reports against configured secret values, JWT/header patterns, credential URLs, prompt/provider bodies, and key prefixes before atomic host write to `ai-service/reports/e2e/`.
- [ ] Ignore generated reports while keeping the directory contract documented.
- [ ] Add a fake local HTTP transport integration test covering session, messages, SSE, report, and failures before real provider use.
- [ ] Run focused tests and `cd ai-service && python3 -m py_compile scripts/e2e_ai_service.py`, then commit Task 3 files.

### Task 4: Run real container/provider validation and fix only proven blockers

**Files:**
- Modify only files directly implicated by a failed E2E scenario or latency trace.
- Add one focused regression test per non-trivial fix.

- [ ] Start `mongodb`, `redis`, and `ai-service` with `docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml up -d --build mongodb redis ai-service`; do not start Mongo Express.
- [ ] Run exact preflight `cd ai-service && python3 scripts/e2e_ai_service.py preflight --env-file .env`, then smoke `cd ai-service && python3 scripts/e2e_ai_service.py smoke --base-url http://127.0.0.1:8001 --env-file .env`.
- [ ] Recreate only `ai-service`, wait at most 180 seconds, and verify the pre-restart session remains readable.
- [ ] Recreate the isolated AI container with `GROQ_SLOT_TELEMETRY=true docker compose -p lexilingo-ai-e2e --env-file ai-service/.env -f ai-service/docker-compose.yml up -d --force-recreate ai-service` and run the synchronized seven-slot scenario; configuration count alone is insufficient.
- [ ] Run `cd ai-service && python3 scripts/e2e_ai_service.py benchmark --base-url http://127.0.0.1:8001 --env-file .env` once and retain its redacted JSON report.
- [ ] For each failed correctness/security gate or measured critical/high bottleneck, trace callers through code-review-graph, add the smallest failing regression test, apply the minimum shared-root fix, and rerun the affected slice.
- [ ] Create `ai-service/docs/technical-debt-e2e.md` only if medium/low findings exist; otherwise record `findings: []` in the retained report.
- [ ] Commit each proven fix separately, then commit the report/debt documentation only if it contains no secrets or environment-specific credentials.

## Chunk 3: Operations, verification, and delivery

### Task 5: Write the server runbook

**Files:**
- Create: `ai-service/docs/production-e2e-runbook.md`
- Modify: `ai-service/README.md`

- [ ] Split variables by stack: isolated AI E2E requires seven unique `GROQ_API_KEYS`, `SECRET_KEY`, `AI_ADMIN_API_KEY`, `REDIS_PASSWORD`, and optional admin-profile `MONGO_EXPRESS_USER/PASSWORD`; root production additionally requires `POSTGRES_PASSWORD`, `ALLOWED_ORIGINS`, and enabled monitoring/provider variables.
- [ ] Document safe `0600` secret-file creation, `git fetch`/pinned checkout, root Compose config/build/up, gateway-level smoke with `curl --fail --show-error https://<host>/health`, bounded logs, and observability checks. Real-provider benchmark runs only against the isolated loopback stack; it is not presented as a root-gateway benchmark.
- [ ] Document how the project-scoped isolated E2E stack can run separately from root production, produce/retrieve its host report, and be stopped without `--volumes`.
- [ ] Document root rollback to the recorded prior commit by recreating only `ai-service`, retaining volumes, and verifying gateway health; document durable pre/post-restart session verification only for the isolated E2E stack.
- [ ] Check every command against current Compose service names and commit Task 5 files.

### Task 6: Full verification and mandated reviews

**Files:**
- Review the recorded implementation-start commit through the final implementation commit, excluding pre-existing user work.

- [ ] Run `cd ai-service && python3 -m pytest -q`, `cd ai-service && python3 -m compileall -q api service scripts`, and `git diff --check`.
- [ ] Run Docker Compose config validation and the final real-provider smoke; run the benchmark again only if performance code changed after the retained report.
- [ ] Dispatch test-writer to find missing public behavior coverage and add only required tests in non-overlapping files.
- [ ] Dispatch security-reviewer for Compose, secrets, JWT, provider telemetry, reports, and runbook; resolve every critical/high finding.
- [ ] Dispatch Kaiser for exercised-path technical debt/bottlenecks; resolve critical/high findings and ledger lower severity.
- [ ] Dispatch code-reviewer for the final diff; resolve correctness regressions.
- [ ] Confirm no raw secret or generated local `.env` is tracked.
- [ ] Commit final review fixes. The user explicitly authorized pushing this branch; push it and report the remote commit plus exact server commands.
