# LexiLingo System Completion — Master Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking. Work phase by phase, in the stated order — later phases assume earlier ones are merged.

**Goal:** Close every product/security gap found by the 2026-08-07 release-readiness audit, so the app can ship without a known revenue-bypass, a core feature (CEFR progress) that never updates from real activity, or a chat assistant that cannot answer basic "how am I doing" questions.

**Supersedes / consolidates:**
- `docs/superpowers/plans/2026-07-28-lexi-system-tools.md` + `specs/2026-07-28-lexi-system-tools-design.md` (never implemented — reused here as Phase 3, content unchanged, folded in for single-file tracking)
- `docs/superpowers/plans/2026-07-03-lexilingo-system-development.md` (Phases 4/6/7/8 never implemented — reused here as Phases 0/1/4/6)
- `docs/superpowers/plans/2026-07-16-system-completion-roadmap.md` (Phase 5/7 — reused here as Phases 7/8, rescoped)
- `docs/superpowers/specs/2026-08-03-backend-audit-remediation-design.md` (remaining batches — reused here as Phase 2)

Those four files stay on disk as historical design record; do not edit them. This file is the single source of truth for what is still outstanding and in what order to build it.

**Tech Stack:** Flutter (Provider, Clean Architecture), FastAPI + SQLAlchemy async (PostgreSQL), Python AI service (LangGraph/TraceCAG, HuBERT), Redis, RevenueCat (`purchases_flutter`), Alembic, pytest, `flutter test`.

---

## Current-state summary (verified against code, 2026-08-07/08)

| Area | Verified state |
|---|---|
| Premium purchases | Client-only. `flutter-app/lib/core/services/purchases_service.dart` checks `RevenueCat` entitlement locally; **no backend model, no route, no webhook** — a rooted/patched client can fake `entitlements.active` and unlock premium server routes for free. |
| CEFR proficiency | `backend-service/app/services/proficiency_service.py::process_exercise_results()` already implements real scoring — **it is just never called** from `routes/learning.py`, games, or content-quiz completion. Profile is frozen at onboarding-time. |
| Pronunciation | `ai-service/api/routes/pronunciation.py` (`assess_pronunciation`) + `ai-service/api/services/hubert_service.py` already exist and work. **Flutter never calls them** — `voice_repository_impl.dart::_calculatePronunciationScore` still does local Levenshtein-style word matching. |
| Today Plan | Full Flutter UI already exists (`today_plan_page.dart`, `today_plan_models.dart`, `today_plan_section.dart`, `today_plan_navigation.dart`) driven by a client-side heuristic. No backend planner. |
| Admin analytics | `routes/analytics.py::get_retention_cohorts` hardcodes `users: 0, d1_retention: 0.0, ...` for all 12 cohort weeks — literally always zero. |
| Lexi chat / system data | Zero code. Plan + spec exist, branch was abandoned, only docs were preserved (commit `53268aa9`). Lexi cannot answer "what's my level / streak / due words" from real data today. |
| Backend security (audit batches) | Better than first assessed: commit `1f50e50d` (PR #388) already shipped centralized SSRF-safe fetch (`app/core/safe_http.py`), fail-closed sensitive-route rate limiting (`app/core/middleware.py`), Alembic single-head verification, and hardened `validate_production_security()`, each with a test. **Not yet verified/closed**: Firebase credential runtime-path rejection, cache-invalidation-after-commit semantics, correlation-ID + secret redaction propagation. Reward/XP `commit=False` convention only partially adopted in `crud/gamification.py`. |
| Observability | `monitoring/prometheus.yml` + `monitoring/rules/alerts.yml` + Grafana exist and are wired into `docker-compose.yml`, but only generic HTTP/process metrics — no TRACE-CAG business metrics (route/cache-hit/cost/learner-state-lag), no canary mode, no kill switch. |
| Ops/product expansion | Learner-state load test exists (`ai-service/tests/load/locustfile_tracecag_learner_state.py`). No admin ops views, no executed backup/restore drill (only an untested systemd timer), no multi-tenant code anywhere. |

## Explicit scope cuts (do not build in this plan)

- **Multi-tenant isolation** (`system-completion-roadmap` Phase 7) — dropped. LexiLingo has no B2B/school-deployment requirement today; building tenant scoping speculatively is pure YAGNI. Revisit only when a real multi-tenant customer is contracted.
- **DriftBench/HotpotQA/MuSiQue benchmark runs, paper writing, ICTA claims** (`system-completion-roadmap` Phases 4/6, `ai-service` benchmark plans) — this is a research/publication track, independent of shipping the product. Do not block release on it; track it separately if still wanted.
- **`docs/Report/RPT-*` admin "benchmark provenance" view** — folded into a single lightweight ops page (Phase 8) instead of a dedicated subsystem; a standalone provenance UI is not worth its own build.

---

## File Map (all phases)

- Create `backend-service/app/models/entitlement.py`, `app/schemas/entitlements.py`, `app/services/entitlement_service.py`, `app/routes/entitlements.py`, `alembic/versions/add_entitlements.py`
- Modify `backend-service/app/main.py`, premium-gated routes, `flutter-app/lib/core/services/purchases_service.dart`
- Modify `backend-service/app/routes/learning.py`, `app/routes/games.py` (or equivalent), content-quiz completion route
- Modify `flutter-app/lib/features/level/presentation/providers/proficiency_provider.dart`
- Create `backend-service/app/core/firebase_credentials.py` guard, modify cache-invalidation call sites, modify `app/core/logging.py`/middleware for redaction
- Modify `flutter-app/lib/features/voice/data/datasources/voice_remote_datasource.dart`, `voice_repository_impl.dart`, `domain/entities/pronunciation_score.dart`
- Create `backend-service/app/schemas/today_plan.py`, `app/services/today_plan_service.py`, `app/routes/today_plan.py`
- Modify Flutter `today_plan_models.dart` + provider to consume the backend route with local-heuristic fallback
- Create `backend-service/app/schemas/learner_context.py`, modify `app/routes/learner_state.py`
- Create `ai-service/api/services/trace_cag/system_data.py`, modify `state.py`, `nodes_v2.py`, `cache_utils.py`, `edges.py`, `generate.py`, `ai-service/api/clients/learner_state_client.py`
- Modify `backend-service/app/routes/analytics.py`, `app/services/achievement_checker_service.py`
- Modify `monitoring/rules/alerts.yml`, add TRACE-CAG metrics exporter, add canary/kill-switch flag in `ai-service/api/core/config.py`
- Create one admin ops page in `admin-service/src` for learner-state/cache-decision visibility

---

## Phase 0 (P0 — revenue/security): Backend Premium Entitlement Enforcement

**Why first:** premium is currently enforced only by trusting the Flutter client's local RevenueCat state. Any modified client or replayed request unlocks paid server features for free. This is the highest-risk item found in the audit.

**Files:** see File Map. Reuses the design already written in `docs/superpowers/plans/2026-07-03-lexilingo-system-development.md` §Chunk 7 — implement it as written, no redesign needed.

### Task 0.1: Entitlement model + sync/read endpoints
- [ ] Add `Entitlement` model (`user_id`, `product_id`, `status`, `expires_at`, `source`) + Alembic migration.
- [ ] Add `POST /api/v1/entitlements/sync` (client submits RevenueCat `CustomerInfo` receipt after purchase/restore) and `GET /api/v1/entitlements/me`.
- [ ] Verify the receipt server-side against RevenueCat's REST API (do not trust the client payload as-is) before writing `status=active`.
- [ ] Write entitlement-service tests: expired, revoked, sandbox vs. production receipt, replay of an old receipt.

### Task 0.2: Guard premium server routes
- [ ] Identify every server route that currently trusts client-side premium state (grep AI/content routes for premium-only behavior) and add a `require_entitlement("premium")` dependency.
- [ ] Free-tier callers get a typed `402`/limit response, not a silent downgrade or a 500.
- [ ] Wire `purchases_service.dart` to call `/entitlements/sync` right after `purchasePackage`/`restorePurchases` succeed, and to prefer the backend's `/entitlements/me` as source of truth on app start (fall back to local RevenueCat state only if the backend call fails).

**Acceptance criteria:** a request to a premium-gated route with a forged/absent client entitlement is rejected server-side; a genuine RevenueCat purchase is reflected in `/entitlements/me` within one sync call; existing free-tier flows are unaffected.

**Exit criteria:** backend + Flutter tests pass; a manual sandbox purchase round-trips through sync → guarded route succeeds → revoke in RevenueCat sandbox → guarded route now rejects.

---

## Phase 1 (P0 — core-feature correctness): CEFR Event Wiring

**Why now:** `ProficiencyService.process_exercise_results()` already contains correct scoring logic — it is dead code today because nothing calls it after a real completion. Shipping like this means the CEFR badge/level shown to users never reflects what they actually did after onboarding.

**Files:** `backend-service/app/routes/learning.py`, games completion route, content-quiz completion route, `app/services/proficiency_service.py` (call site only, no logic change), `flutter-app/lib/features/level/presentation/providers/proficiency_provider.dart`.

### Task 1.1: Wire real completions into proficiency
- [ ] Enumerate every route that finalizes a scoreable result: lesson/course completion, game-session end, content-quiz submit.
- [ ] Normalize each into the `ExerciseResult` shape `process_exercise_results` already expects.
- [ ] Call `process_exercise_results` after commit of the underlying completion record, inside the same request — not via a background job (keep it simple; add async offload only if latency profiling later proves it necessary).
- [ ] Add an idempotency guard so a duplicate/retried completion request does not double-count XP/level progress (mirrors the existing `(user_id, source, source_id)` XP-award invariant from the backend audit).
- [ ] Write one integration test per completion type proving the CEFR profile actually changes, and one proving a duplicate submit does not inflate it.

**Acceptance criteria:** completing a lesson, a game, or a content quiz visibly moves the user's CEFR profile in the same session; replaying the same completion is a no-op.

**Exit criteria:** focused backend tests pass; manual smoke shows `proficiency_provider.dart` reflecting a level-progress change right after a real completion.

---

## Phase 2 (P0 — security remediation, remaining batches): Close the Backend Audit

**Why now:** most of `docs/superpowers/specs/2026-08-03-backend-audit-remediation-design.md` shipped already in `1f50e50d` (SSRF, sensitive-route rate limiting, Alembic single-head, security config validation). Three batches are still open plus one needs full verification.

**Files:** `backend-service/app/crud/*.py`, `app/core/firebase_credentials.py` (new), cache-invalidation call sites (post-XP-award, post-content-update), `app/core/logging.py`/request middleware.

### Task 2.1: Verify/complete reward-XP atomicity (spec batch 1–2)
- [ ] Audit every `crud/gamification.py` write path for the `commit=False`, service-owns-commit convention; fix any remaining caller that commits early.
- [ ] Add a PostgreSQL concurrency test: two simultaneous XP-award requests for the same `(user_id, source, source_id)` must produce exactly one award.

### Task 2.2: Firebase credential production guard (spec batch 6)
- [ ] Reject any production boot where a Firebase service-account JSON path resolves inside the repository tree; require runtime/default credentials in production (mirrors the OAuth-audience hardening already done for Google auth).
- [ ] Add a negative test: production settings + repo-relative credential path → startup fails closed.

### Task 2.3: Cache invalidation after commit (spec batch 8)
- [ ] Ensure XP/content cache invalidation only fires after the owning transaction commits successfully.
- [ ] Test: commit succeeds + invalidation fails → request still reports success, and a bounded TTL guarantees eventual consistency (no outbox needed unless this test proves TTL insufficient).

### Task 2.4: Logging propagation + redaction (spec batch 11)
- [ ] Propagate the existing correlation/request ID through outbound calls and any background job touched by Phases 0–1 above.
- [ ] Redact `Authorization`, cookies, API keys, and other known secret fields in logs on those paths.
- [ ] Give mandatory readiness-check dependencies short timeouts; never expose internal hostnames or raw exception text in the response body.

**Exit criteria:** `backend-service/BACKEND_AUDIT_REPORT.md` updated with final status per item; security review has no unresolved finding against these four items.

---

## Phase 3 (P1 — chat UX): Lexi System Data Tools

**Why now, not P0:** this is a chat-quality gap (Lexi can't answer "what's my level"), not a correctness or security risk — safe to ship one release without it, but it's the single most-requested-feeling gap once premium/CEFR/security are fixed.

**Files + tasks:** unchanged from `docs/superpowers/plans/2026-07-28-lexi-system-tools.md` (478 lines, already fully speced — fixed selector in TraceCAG state, cache-bypassed snapshot fetch through the pooled learner-state client, shared prompt grounding for regular + SSE). Implement it exactly as written there; it was never built, not because the design was rejected. Copy its 6 tasks into execution as-is:

- [ ] Task 3.1 (= plan Task 1): backend read-only learner snapshot endpoint (`GET /internal/learner-state/users/{user_id}/context`).
- [ ] Task 3.2 (= plan Task 2): extend the pooled `LearnerStateClient` with `get_learning_snapshot`.
- [ ] Task 3.3 (= plan Task 3): fixed selector (`select_system_tool`) + safe prompt serialization, new `system_tool`/`system_context` state fields.
- [ ] Task 3.4 (= plan Task 4): wire selection + L0/L1 cache bypass + concurrent snapshot fetch into `nodes_v2.py`/`cache_utils.py`/`edges.py`.
- [ ] Task 3.5 (= plan Task 5): ground both regular and SSE generation paths via one shared `_append_system_data_block` helper, with a bounded extractive-mode response.
- [ ] Task 3.6 (= plan Task 6): end-to-end verification — backend+AI suites, static/compose checks, deterministic cross-service E2E, production-like smoke against `https://api.lexilingo.me`, privacy/latency assertions on the 300ms deadline.

**Exit criteria:** identical to the source plan's Task 6 — full test suites pass, one authenticated progress-question request produces a grounded answer, zero snapshot calls for ordinary grammar chat, timeout still yields a response, no PII in logs/cache.

---

## Phase 4 (P1): Server-Side Today Plan

**Files:** `backend-service/app/schemas/today_plan.py`, `app/services/today_plan_service.py`, `app/routes/today_plan.py`; Flutter `today_plan_models.dart` + its provider (UI screens already exist, do not rebuild them).

### Task 4.1: Backend planner
- [ ] Service computes today's recommended items from due vocabulary, open mistakes (from the mistake notebook, already synced), weak skills, and streak state — no AI-service dependency, pure backend logic.
- [ ] Each item carries a stable ID, a completion state, and a one-line "why recommended" reason.
- [ ] `GET /api/v1/today-plan` (authenticated).

### Task 4.2: Flutter wiring
- [ ] Provider calls the backend route first; keep the existing client-side heuristic as the offline/error fallback, don't delete it.
- [ ] Completion state round-trips to the backend so a completed item stays completed across sessions/devices.

**Acceptance criteria:** plan items are explainable and stable across app restarts; app still functions with a plausible plan when the backend is unreachable.

---

## Phase 5 (P1): Wire Pronunciation Coach to the Existing HuBERT Endpoint

**Why this is smaller than it looks:** the backend (`ai-service/api/routes/pronunciation.py`, `hubert_service.py`) is done and working. This is a Flutter-only wiring task.

**Files:** `flutter-app/lib/features/voice/data/datasources/voice_remote_datasource.dart`, `data/repositories/voice_repository_impl.dart`, `domain/entities/pronunciation_score.dart`.

### Task 5.1: Prefer backend scoring, keep local as fallback
- [ ] Add a remote call from `voice_remote_datasource.dart` to `assess_pronunciation`.
- [ ] Map its phoneme-level scores/error details onto `pronunciation_score.dart`'s domain entity.
- [ ] `voice_repository_impl.dart`: try the backend call first; on failure/offline, fall back to the existing `_calculatePronunciationScore` heuristic unchanged.

**Acceptance criteria:** voice practice shows phoneme-level feedback when online; still produces a usable score offline or on API failure.

---

## Phase 6 (P1): Replace Placeholder Analytics

**Files:** `backend-service/app/routes/analytics.py`, `app/services/achievement_checker_service.py`.

### Task 6.1: Real cohort retention
- [ ] Replace the hardcoded-zero `get_retention_cohorts` body with a real DB aggregation: signup-week cohorts joined against `daily_activities` for D1/D7/D30 presence.
- [ ] Same treatment for any other placeholder achievement-stat computation in `achievement_checker_service.py`.
- [ ] Backend tests asserting non-trivial retention numbers on a seeded fixture.

**Acceptance criteria:** admin dashboard retention chart reflects actual `daily_activities` rows, not zeros, on any populated environment.

---

## Phase 7 (P2 — deferred until after the above): Production Observability

**Rescoped from `system-completion-roadmap` Phase 5 — infra half already exists, this phase adds only the missing business layer.**

**Files:** `monitoring/rules/alerts.yml`, a small metrics-exporter addition in `ai-service/api/services/trace_cag/`, one config flag in `ai-service/api/core/config.py`.

### Task 7.1: TRACE-CAG business metrics + alerts
- [ ] Export counters/histograms already computable from existing state: route decision counts, cache hit/miss, hard-reject count, patch count, latency by route, token cost, learner-state lag.
- [ ] Add alert rules for unsafe-acceptance rate, certificate-mismatch spikes, cache-invalidation storms, provider quota errors, queue growth — reuse the existing Prometheus/Grafana stack, do not stand up a second monitoring system.

### Task 7.2: Canary + kill switch
- [ ] One config flag that forces full generation (bypasses cache/patch shortcuts) for a percentage of traffic or on manual trigger — this is the safety valve if Phase 3's cache-bypass logic misbehaves in production.

**Exit criteria:** a 24-hour soak shows the new dashboards populated, no unbounded retry/queue growth, and the kill switch verifiably forces full generation when flipped.

---

## Phase 8 (P2 — deferred): Minimal Ops Visibility + Backup Drill + Load Test Extension

**Rescoped from `system-completion-roadmap` Phase 7 — multi-tenant dropped (see scope cuts); everything else trimmed to what's actually actionable.**

### Task 8.1: One admin ops page
- [ ] Single `admin-service` page showing learner-state sync lag/consistency and recent cache-gate decisions (route/reason breakdown from Phase 7's new metrics). Do not build a separate "benchmark provenance" subsystem — link out to `docs/Report/` if that's ever needed.

### Task 8.2: Execute and document a real backup/restore drill
- [ ] The systemd backup timer (`deploy/systemd/lexilingo-backup.service`) already runs — actually restore from one of its backups into a scratch database and record the RPO/RTO achieved in `docs/operations/BACKUP_RESTORE_POLICY.md`. This is a drill to run and document, not new code.

### Task 8.3: Extend the existing load test
- [ ] Broaden `locustfile_tracecag_learner_state.py`'s scope (or add a sibling file) to cover a full concurrent-learner session, not just learner-state calls — reuse its existing harness/patterns.

**Exit criteria:** admin page shows live data; one documented restore drill with measured RPO/RTO exists; load test report covers a realistic concurrent-session profile.

---

## Recommended execution order

`Phase 0 (entitlements) → Phase 1 (CEFR wiring) → Phase 2 (security remediation close-out) → Phase 3 (Lexi system tools) → Phase 4 (today plan) → Phase 5 (pronunciation wiring) → Phase 6 (analytics) → Phase 7 (observability) → Phase 8 (ops/backup/load)`

Phases 0–2 are release blockers (revenue leak, core-feature correctness, open security items). Phases 3–6 are product-completeness work that should land before or shortly after the same release. Phases 7–8 are explicitly P2 and can trail the release without blocking it.

## Definition of done for "release ready"

- Phases 0–2 merged, tested, and their acceptance criteria demonstrated against a staging environment (not just unit tests).
- Phases 3–6 merged or explicitly deferred with the product owner's sign-off (not silently dropped).
- Production data-migration status (separate open question from the 2026-08-07 audit — see `docs/operations/system-completion-server-handoff-2026-07-16.md`) confirmed with the server operator before shipping, independent of this plan.
