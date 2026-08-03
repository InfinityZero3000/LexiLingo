# Backend Audit Remediation Design

## Scope

Complete the thirteen audit items identified as partially implemented during repository verification. Work is split into independently reviewable batches.

| Audit item | Current evidence | Missing guarantee | Batch |
|---|---|---|---|
| #1 Reward/XP atomicity | User/wallet/leaderboard locks and reward uniqueness exist | Consistent service-owned transaction and real concurrent requests | 1–2 |
| #2 Streak/challenge races | Challenge claim uniqueness exists | Locked streak/progress writes and concurrent completion tests | 3 |
| #3 Alembic clean build | Revision graph has one head | Empty-DB and supported-upgrade CI path | 4 |
| #4 SSRF | News validates redirects; podcast has partial IP checks | One pinned safe transport, HTTPS-only, all address/redirect/size cases | 5 |
| #5 OAuth verification | Configured Google audience is checked | Production-required audience and negative issuer/type/client tests | 6 |
| #6 Firebase credentials | Ignore rules and Gitleaks exist | Production source-tree rejection and runtime credential path | 7 |
| #8 Cache invalidation | Some XP invalidation occurs after commit | Shared post-commit semantics and bounded failure behavior | 8 |
| #9 Rate limiting | Redis counters and local fallback exist | Atomic expiry and enumerated fail-closed sensitive routes | 9 |
| #12 Security config | Some production validators exist | Complete secret/list/URL validation | 10 |
| #13 DB invariants | Challenge uniqueness and wallet check migration exist | Model parity and remaining included reward/status invariants | 3–4 |
| #14 Logging | Request ID exists | Propagation and secret redaction in touched paths | 11 |
| #15 Health probes | Liveness/readiness routes exist | Dependency timeouts and mandatory-dependency policy | 11 |
| #16 Module responsibilities | Some service extraction exists | Only targeted cleanup arising from batches 1–11 | Each batch |

Items #7 (partner-key lifecycle), #10 (background-task leasing), and #11 (error-response sanitization) are excluded because verification classified them as not implemented, and the user approved limiting this effort to partially implemented items.

## Delivery Process

Each group follows the same gate:

1. Add a regression or integration test that demonstrates the missing guarantee.
2. Apply the smallest root-cause change in the shared path.
3. Run focused tests and the required integration/CI check. A missing dependency is a documented blocker, not permission to mark the batch complete.
4. Run security review for routes, auth, configuration, or migrations.
5. Run code review and resolve every finding that violates the batch guarantees before starting the next batch.
6. Update `backend-service/BACKEND_AUDIT_REPORT.md` with evidence and status.

Existing user changes in the dirty worktree must be preserved. No broad refactor or new framework is introduced.

## Batches 1–3: Transaction and Race Safety

1. Establish the transaction convention: service owns commit; nested CRUD supports `commit=False`.
2. Complete reward/XP atomicity with PostgreSQL concurrency tests for simultaneous awards.
3. Complete streak/challenge locking, idempotency, and database invariants with simultaneous update/claim tests.

Only mutations required by audit items #1/#2 are included. Leaderboard or daily-activity rows are changed only where they are part of the same XP transaction.

## Batches 4–7: Migration and Security

4. Add Alembic clean-build/upgrade CI. Released revisions are immutable; any repair uses a new forward migration unless deployment history proves a revision has never shipped. A checked-in migration-test manifest defines the supported starts as `base` (empty), `add_learner_concept_state` (the parent before the audit-fix revisions), and `head-1`; CI builds each state with Alembic and upgrades to `head`. It also runs empty PostgreSQL through `upgrade head → downgrade -1 → upgrade head`. A revision requiring data fixtures must declare its fixture in the manifest; a missing declared fixture blocks completion. Backfill failure tests must prove rollback and a successful retry.
5. Centralize SSRF-safe fetching. User-controlled URLs require HTTPS; every resolved address must be globally routable. The transport must connect only to a validated/pinned address while preserving the original TLS hostname/SNI, and repeat resolution/pinning for every redirect. Enforce redirect count, timeout, content-length and decompressed-byte limits. Test IPv4, IPv6, mixed public/private DNS answers, rebinding, and redirects to metadata/private targets.
6. Require configured Google audiences in production and reject missing/wrong audience, issuer, client, or provider type with negative tests.
7. Keep Firebase Admin SDK verification, reject production credential paths inside the repository, and use runtime/default credentials where supported.

## Batches 8–9: Runtime Reliability

8. Cache invalidation occurs only after a successful commit. Test that commit success plus invalidation failure still reports committed success, cached values have a verified bounded TTL, and later reads converge. The accepted stale window is that configured TTL; no outbox is introduced unless this guarantee cannot be met.
9. Redis rate limiting uses one atomic operation with expiry. A checked-in sensitive-route registry, consumed by both middleware and parameterized tests, contains: `POST /api/v1/auth/login`, `POST /api/v1/auth/register`, `POST /api/v1/auth/forgot-password`, `POST /api/v1/auth/admin/login`, `POST /api/v1/auth/admin/request-otp`, `POST /api/v1/auth/admin/verify-otp`, `POST /api/v1/xp/award`, `POST /api/v1/challenges/daily/bonus/claim`, `POST /api/v1/challenges/daily/{challenge_id}/claim`, and `GET /api/v1/integrations/**`. Registered routes fail closed with `503` and `Retry-After` when the distributed limiter is unavailable, and return `429` plus `Retry-After` when exhausted. Ordinary routes retain bounded local fallback.

## Batches 10–11: Configuration and Observability

10. Production validation rejects default/empty secrets, wildcard or local CORS, insecure upstream URLs, and ambiguous list values.
11. Propagate correlation IDs through outbound calls and background jobs touched by this work, redact authorization/cookies/API keys/known secret fields, and give mandatory readiness dependencies short timeouts without exposing internal hosts or exception text. Liveness remains process-only.

## Targeted Cleanup

Move logic only when a modified router currently owns a transaction, outbound-security policy, or other shared business rule. Reuse existing services and helpers. Do not create interfaces, factories, or speculative modules.

For item #13, the explicit invariants are: wallet gems never negative; one starter reward per `(user_id, reward_key)`; one XP award per non-null `(user_id, source, source_id)`; one daily activity per `(user_id, activity_date)`; one streak row per user; and one challenge claim per `(user_id, challenge_id, claim_date)`. Model metadata and forward migrations must agree.

Item #16 is structural: its evidence is unchanged public behavior under the batch tests plus code-review confirmation that transaction/security rules moved out of routers where touched, no new one-implementation abstraction was added, and no touched function gained unrelated responsibilities.

## Completion Criteria

- Every included behavioral audit item has implementation evidence and an executable regression test; item #16 uses the structural review evidence defined above.
- PostgreSQL concurrency and Alembic clean-build checks pass.
- Focused security review and code review have no unresolved finding that violates a batch guarantee.
- The audit report records completed status and exact test commands.
