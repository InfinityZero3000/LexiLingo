# LexiLingo System Completion — Master Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking. Work phase by phase, in the stated order — later phases assume earlier ones are merged.

**Goal:** Close every product/security gap found by the 2026-08-07 release-readiness audit, so the app can ship without a known revenue-bypass, a core feature (CEFR progress) that never updates from real activity, or a chat assistant that cannot answer basic "how am I doing" questions.

**Supersedes / consolidates** (source files deleted 2026-08-09 after folding their content in here — see git history for the originals if needed):
- `docs/superpowers/plans/2026-07-28-lexi-system-tools.md` + `specs/2026-07-28-lexi-system-tools-design.md` (never implemented — reused here as Phase 3, content unchanged, folded in for single-file tracking)
- `docs/superpowers/plans/2026-07-03-lexilingo-system-development.md` (Phases 4/6/7/8 never implemented — reused here as Phases 0/1/4/6)
- `docs/superpowers/plans/2026-07-16-system-completion-roadmap.md` (Phase 5/7 — reused here as Phases 7/8, rescoped)
- `docs/superpowers/specs/2026-08-03-backend-audit-remediation-design.md` (remaining batches — reused here as Phase 2)

This file is the single source of truth for what is still outstanding and in what order to build it.

**Tech Stack:** Flutter (Provider, Clean Architecture), FastAPI + SQLAlchemy async (PostgreSQL), Python AI service (LangGraph/TraceCAG, HuBERT), Redis, RevenueCat (`purchases_flutter`), Alembic, pytest, `flutter test`.

---

## Execution log (2026-08-08/09)

| Phase | Status | Notes |
|---|---|---|
| **0 — Entitlements** | ✅ Task 0.1 done, ⏸️ Task 0.2 deliberately skipped | Backend `UserEntitlement` model/route/service shipped, verified against RevenueCat server-side. Task 0.2 ("guard premium routes") not done: grepped the whole app and found **zero routes or screens currently gate anything behind premium** — `PremiumGate`/`PaywallScreen` exist but are wired to nothing. `require_entitlement()` dependency is built and ready but has no route to attach to yet; needs a product decision on what (if anything) is actually premium before Task 0.2 has meaning. |
| **1 — CEFR wiring** | ✅ Done | `record_exercise_results_for_user()` extracted from the pre-existing `/proficiency/record-exercises` route, now called from `complete_lesson` and `complete_game_session` with `award_xp=False` (that function has its own XP bonus, which would otherwise double-award on top of what those routes already grant). Content-quiz completion **not wired** — no submit endpoint exists yet for it, out of scope of "wire what's already there." Found and fixed a live bug via testing: `calculate_skill_score` crashed on a user's first exercise per skill (`UserSkillScore.score` is `None` until the ORM default flushes) — independently fixed on `dev` in parallel during the same window, reconciled during rebase. |
| **2 — Security remediation** | ✅ Done, re-scoped | 3 of 4 batches (#6 Firebase creds, #8 cache invalidation, #11 logging/redaction) turned out to already be shipped on `dev` mid-session by unrelated work (commit `9d26e32e`). Batch #1-2 (reward/XP atomicity) re-verified by reading every write path (`unlock_achievement`, `LeaderboardCRUD.add_xp`, `award_xp_transaction`, `starter_reward_service`) — all already race-safe (unique constraints / `FOR UPDATE` locks); added `tests/services/test_xp_award_concurrency.py`, passed against live Postgres. |
| **3 — Lexi system tools** | ⬜ Not started | Design unchanged from source plan, ready to execute. |
| **4 — Today Plan backend** | ⬜ Not started | |
| **5 — Pronunciation wiring** | ⬜ Not started | |
| **6 — Analytics** | ⬜ Not started | |
| **7 — Observability** | ⬜ Not started | |
| **8 — Ops/backup/load** | ⬜ Not started | |

**Review + deploy:** Phases 0-2 went through an independent code-reviewer + security-reviewer pass (no CRITICAL/HIGH findings; 3 real bugs found and fixed — RevenueCat missing-key raising an unhandled 500 on every login, rank going stale on a `award_xp=False` CEFR level-up, an entitlement-sync dedupe flag that could never retry after a failed sync). Merged to `dev` (fast-forward, `936894ed`), full 1440-test backend suite passed against live Postgres. Pulled and deployed to production (`sgp1-01-lexi`, `/opt/lexilingo`) — surfaced and fixed one unrelated pre-existing production misconfiguration in the process: `docker-compose.yml` mounted the Firebase service-account file at `/app/firebase-service-account.json`, which the new (already-on-`dev`) production-config validator correctly rejects as "inside the project source tree," crash-looping `backend-service` on first redeploy since that validator landed. Fixed by remounting to `/run/secrets/firebase-service-account.json` (commit `3ef266ca`). Production confirmed healthy, `https://api.lexilingo.me/health` returns 200.

---

## Current-state summary (verified against code, 2026-08-07/08)

| Area | Verified state |
|---|---|
| Premium purchases | **Backend infra shipped** (`app/models/entitlement.py`, `revenuecat_client.py`, `entitlement_service.py`, `POST /entitlements/sync`, `GET /entitlements/me`, `require_entitlement()` dependency) — server-verified against RevenueCat's API, no client payload trusted. **Still nothing to guard**: confirmed zero premium-gated routes/screens exist in the product. Not currently exploitable (nothing to steal), but also not yet doing anything — needs a product decision on what's premium before `require_entitlement()` gets attached anywhere. |
| CEFR proficiency | **Wired.** `record_exercise_results_for_user()` (extracted from the old `/proficiency/record-exercises` route) is now called from real lesson and game completions. Content-quiz path still has no submit endpoint to wire. |
| Pronunciation | `ai-service/api/routes/pronunciation.py` (`assess_pronunciation`) + `ai-service/api/services/hubert_service.py` already exist and work. **Flutter still never calls them** — `voice_repository_impl.dart::_calculatePronunciationScore` still does local Levenshtein-style word matching. Untouched — Phase 5. |
| Today Plan | Full Flutter UI already exists (`today_plan_page.dart`, `today_plan_models.dart`, `today_plan_section.dart`, `today_plan_navigation.dart`) driven by a client-side heuristic. No backend planner. Untouched — Phase 4. |
| Admin analytics | `routes/analytics.py::get_retention_cohorts` hardcodes `users: 0, d1_retention: 0.0, ...` for all 12 cohort weeks — literally always zero. Untouched — Phase 6. |
| Lexi chat / system data | Zero code. Plan + spec exist, branch was abandoned, only docs were preserved (commit `53268aa9`). Lexi cannot answer "what's my level / streak / due words" from real data today. Untouched — Phase 3. |
| Backend security (audit batches) | **All 4 remaining batches now closed.** #6 (Firebase credential guard), #8 (cache invalidation timing), #11 (logging/redaction) shipped on `dev` mid-session (commit `9d26e32e`) — though #6's own `docker-compose.yml` mount was self-inconsistent with the new rule and crash-looped production on first redeploy; fixed (commit `3ef266ca`). #1-2 (reward/XP atomicity) verified already race-safe everywhere, now with a passing concurrency regression test. |
| Observability | `monitoring/prometheus.yml` + `monitoring/rules/alerts.yml` + Grafana exist and are wired into `docker-compose.yml`, but only generic HTTP/process metrics — no TRACE-CAG business metrics (route/cache-hit/cost/learner-state-lag), no canary mode, no kill switch. Untouched — Phase 7. |
| Ops/product expansion | Learner-state load test exists (`ai-service/tests/load/locustfile_tracecag_learner_state.py`). No admin ops views, no executed backup/restore drill (only an untested systemd timer), no multi-tenant code anywhere. Untouched — Phase 8. |

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

### Task 0.1: Entitlement model + sync/read endpoints — ✅ DONE
- [x] Add `Entitlement` model (`user_id`, `product_id`, `status`, `expires_at`, `source`) + Alembic migration. — `app/models/entitlement.py`, `alembic/versions/74b24453f92f_add_user_entitlements_table.py`
- [x] Add `POST /api/v1/entitlements/sync` and `GET /api/v1/entitlements/me`. — `app/routes/entitlements.py`. Design deviation: the sync endpoint takes **no client payload at all** — it just triggers the backend to re-fetch straight from RevenueCat's API using the authenticated user's id, which is stronger than "verify the client's submitted receipt" (nothing client-supplied is ever trusted, not even to select which product).
- [x] Verify server-side against RevenueCat's REST API. — `app/services/revenuecat_client.py`. Fail-closed on new grants / fail-open on already-confirmed ones during a RevenueCat outage (tested); missing `REVENUECAT_SECRET_API_KEY` treated the same as an outage, not a 500 (bug found + fixed post-review — see `tests/services/test_entitlement_service.py::test_missing_secret_key_is_degraded_not_a_500`).
- [x] Write entitlement-service tests. — `tests/services/test_entitlement_service.py` (7 cases: create/expire/none/outage×2/upsert/missing-key).
- [x] Flutter: linked RevenueCat's `app_user_id` to the backend user id via `identifyUser()` (was never called anywhere before this) and sync entitlements once per login, in `auth_wrapper.dart::_syncEntitlements` — mirrors the existing `_resolvePostAuthFlow` dedupe-by-userId pattern already used there. `PurchasesService.instance.logout()` added to sign-out (was also missing — device-shared-login identity leak risk).

### Task 0.2: Guard premium server routes — ⏸️ SKIPPED, not a gap
- [ ] ~~Identify every server route that currently trusts client-side premium state~~ — grepped the entire backend + Flutter: **no route or screen gates anything behind premium today.** `PremiumGate` widget and `PaywallScreen` exist but are used nowhere. There is nothing to guard, and inventing what should be premium is a product decision, not an engineering one. `require_entitlement()` (in `app/core/dependencies.py`) is built, tested, and ready — attach it to a route whenever the product decision lands.

**Acceptance criteria:** a request to a premium-gated route with a forged/absent client entitlement is rejected server-side; a genuine RevenueCat purchase is reflected in `/entitlements/me` within one sync call; existing free-tier flows are unaffected.

**Exit criteria:** backend + Flutter tests pass; a manual sandbox purchase round-trips through sync → guarded route succeeds → revoke in RevenueCat sandbox → guarded route now rejects.

---

## Phase 1 (P0 — core-feature correctness): CEFR Event Wiring

**Why now:** `ProficiencyService.process_exercise_results()` already contains correct scoring logic — it is dead code today because nothing calls it after a real completion. Shipping like this means the CEFR badge/level shown to users never reflects what they actually did after onboarding.

**Files:** `backend-service/app/routes/learning.py`, games completion route, content-quiz completion route, `app/services/proficiency_service.py` (call site only, no logic change), `flutter-app/lib/features/level/presentation/providers/proficiency_provider.dart`.

### Task 1.1: Wire real completions into proficiency — ✅ DONE (lesson + game; content-quiz has no endpoint yet)
- [x] Enumerate every route that finalizes a scoreable result — found `complete_lesson` (`routes/learning.py`) and `complete_game_session` (`routes/games.py`). Content-quiz has no submit endpoint in the codebase at all (news quiz is `GET`-only) — building one is new scope, not "wiring what exists," left for a future pass.
- [x] Normalize each into `ExerciseResult`. — one aggregate result per completion (not per-question — `QuestionAttempt` has no skill/CEFR-level field to build fine-grained results from); `ProficiencyService.infer_skill_from_tags()` added as the skill-inference heuristic for lessons (from `Course.tags`) and games (from `game_type`).
- [x] Call after commit, same request. — extracted the manual route's logic into `record_exercise_results_for_user()` (`routes/proficiency.py`), called from both completion routes right after their own `db.commit()`.
- [x] Idempotency — both completion routes already had their own replay guards (`finished_at`/`completed_at`+`xp_awarded`); that's the boundary, no new guard needed. Real gap found instead: `record_exercise_results_for_user()` grants its own small XP bonus independent of the caller — calling it after a route that already awarded XP double-counts. Added `award_xp: bool = True` param, both call sites pass `award_xp=False`.
- [x] Tests — `tests/routes/test_record_exercise_results_for_user.py`. Root-cause bug found via testing: `calculate_skill_score` crashed (`TypeError`) on a user's first exercise per skill because a freshly-created `UserSkillScore.score` is `None` until the ORM default flushes — fixed at the source (also independently fixed on `dev` in parallel; reconciled during rebase, kept `dev`'s `normalized_current_score` naming). Second bug found by code review: rank went stale on an `award_xp=False` CEFR level-up (`current_user.level` synced but `calculate_rank()` only ran `if award_xp`) — fixed to recalculate whenever `level_changed`, verified by reverting the fix and confirming the test failed (`0.0 != 13.33`) before re-applying.

**Acceptance criteria:** completing a lesson, a game, or a content quiz visibly moves the user's CEFR profile in the same session; replaying the same completion is a no-op.

**Exit criteria:** focused backend tests pass; manual smoke shows `proficiency_provider.dart` reflecting a level-progress change right after a real completion.

---

## Phase 2 (P0 — security remediation, remaining batches): Close the Backend Audit

**Why now:** most of `docs/superpowers/specs/2026-08-03-backend-audit-remediation-design.md` shipped already in `1f50e50d` (SSRF, sensitive-route rate limiting, Alembic single-head, security config validation). Three batches are still open plus one needs full verification.

**Files:** `backend-service/app/crud/*.py`, `app/core/firebase_credentials.py` (new), cache-invalidation call sites (post-XP-award, post-content-update), `app/core/logging.py`/request middleware.

### Task 2.1: Verify/complete reward-XP atomicity (spec batch 1–2) — ✅ DONE
- [x] Audited every reward/XP write path by reading (not grepping) each one: `unlock_achievement` (unique constraint + `IntegrityError` catch), `LeaderboardCRUD.add_xp` (`FOR UPDATE`), `award_xp_transaction`/`xp_service.py` — the path lesson/game completion actually uses (`FOR UPDATE` + unique `(user_id, source, source_id)` index + `IntegrityError` handling), `starter_reward_service.grant_new_user_reward` (`db.begin_nested()` savepoint + unique constraint). **All already race-safe** — no code change needed. First-pass grep-based assessment ("5-6 functions missing `commit=False`") was a false positive: conflated a composability convention with an actual race-safety property.
- [x] Concurrency test — `tests/services/test_xp_award_concurrency.py`: two sessions racing to award XP for the identical `(user_id, source, "race-test-session-1")`; asserts exactly one `XPTransaction` row. **Passed against live Postgres** with real row-locking.

### Task 2.2: Firebase credential production guard (spec batch 6) — ✅ Already done on `dev`, one deploy-config bug fixed
- [x] `validate_production_security()` already rejects `FIREBASE_CREDENTIALS_FILE` resolving inside `PROJECT_ROOT` — shipped on `dev` (commit `9d26e32e`) during this session, independent of this plan.
- [x] Found live in production: `docker-compose.yml` mounted the credential file at `/app/firebase-service-account.json` — inside `PROJECT_ROOT` by the validator's own definition — so the *first* real redeploy after that validator landed crash-looped `backend-service`. Fixed the mount target to `/run/secrets/firebase-service-account.json` (commit `3ef266ca`), updated `.env.production` on the server to match, confirmed healthy.

### Task 2.3: Cache invalidation after commit (spec batch 8) — ✅ Already done on `dev`
- [x] `xp_service.py::award_xp_transaction` (the live XP path) already invalidates the leaderboard cache only inside `if commit:`, after `db.commit()` succeeds, with correct `IntegrityError`/race handling. `starter_reward_service` cache invalidation similarly fixed on `dev` (commit `9d26e32e`, item #8 in its own message) during this session.

### Task 2.4: Logging propagation + redaction (spec batch 11) — ✅ Already done on `dev`, applies automatically
- [x] `app/core/logging_config.py` (shipped on `dev` mid-session) wires `RequestIDLogFilter` + `RedactSecretsLogFilter` into the root logger globally — correlation ID via `contextvars` (propagates across `await` automatically) and Authorization/api_key/password/token redaction apply to every log call in this codebase, including the new Phase 0/1 code, with no extra wiring needed on this end. Considered and skipped adding `X-Request-ID` to the outbound RevenueCat HTTP call — that's `safe_http.py`'s pattern for arbitrary less-trusted URLs, not what similar fixed-trusted-host clients like `content_agent_client.py` do either.

**Exit criteria:** met — `BACKEND_AUDIT_REPORT.md` items #1/#2/#6/#8/#11 all closed; independent code-reviewer + security-reviewer pass found no unresolved CRITICAL/HIGH finding.

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

**Phases 0–2 done and deployed to production** (see Execution log above). Phases 3–6 are the next block — product-completeness work, no P0 blocker among them. Phases 7–8 remain explicitly P2 and can trail without blocking anything.

## Definition of done for "release ready"

- [x] Phases 0–2 merged, tested, and deployed to production (`api.lexilingo.me`, confirmed healthy 2026-08-09).
- [ ] Phases 3–6 merged or explicitly deferred with the product owner's sign-off (not silently dropped).
- [ ] Production data-migration status (separate open question from the 2026-08-07 audit — see `docs/operations/system-completion-server-handoff-2026-07-16.md`) confirmed with the server operator before shipping, independent of this plan.
