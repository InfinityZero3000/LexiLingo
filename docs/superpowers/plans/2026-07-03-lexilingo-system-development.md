# LexiLingo System Development Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the current system audit into a sequence of small, testable improvements that make LexiLingo's learning loop more personalized, production-ready, and measurable.

**Architecture:** Work incrementally across the existing FastAPI backend, AI service, Flutter app, and admin dashboard. Start with low-risk feature gaps that already have routes or UI surfaces, then move toward cross-service features such as synced mistakes, unified pronunciation, planner, premium enforcement, and analytics.

**Tech Stack:** FastAPI, SQLAlchemy async, Alembic, pytest, Flutter Provider/Repository pattern, SharedPreferences, RevenueCat, React admin, GitHub Actions.

---

## Scope And Evidence

This plan is based on a read-only system audit. `code-review-graph` reported 1327 files, 12800 nodes, and 96934 edges; architecture community output was empty and hotspot tools failed with an internal path-resolution error, so direct source inspection is used for feature-level evidence.

Key gaps to close:

- News quiz generation is still placeholder logic in `backend-service/app/routes/news.py`.
- Mistake notebook entries are local-only in `flutter-app/lib/features/mistakes/data/mistake_notebook_repository.dart`.
- General voice practice still scores pronunciation from transcript similarity in `flutter-app/lib/features/voice/data/repositories/voice_repository_impl.dart` instead of the HuBERT pronunciation pipeline.
- Today plan is client-side heuristic logic in `flutter-app/lib/features/home/presentation/widgets/home_page/today_plan_models.dart`.
- CEFR proficiency recording exists but is not consistently wired into all learning completion flows.
- Premium gating is client-side and lacks backend entitlement enforcement.
- Several analytics, achievement, and CI surfaces remain placeholder or partial.

## File Map

### Phase 1: Content Learning Quality

- Modify: `backend-service/app/routes/news.py`
  - Replace placeholder news quiz with deterministic article-aware quiz generation and optional article context.
- Modify: `backend-service/tests/test_news_routes.py`
  - Add unit tests that prevent placeholder options/explanations from returning.
  - Add tests for article-aware vocabulary and comprehension generation.

### Phase 2: Synced Mistake Notebook

- Create: `backend-service/app/models/mistake.py`
  - Store user mistake notebook entries with source metadata, prompt, expected answer, selected answer, skill, status, and timestamps.
- Create: `backend-service/app/schemas/mistakes.py`
  - Request/response schemas for create, list, resolve, and delete.
- Create: `backend-service/app/routes/mistakes.py`
  - Authenticated `/mistakes` API for user-owned entries.
- Modify: `backend-service/app/main.py`
  - Include the new mistakes router.
- Modify: `backend-service/app/models/__init__.py`
  - Export the new model for metadata registration.
- Create: `backend-service/alembic/versions/add_mistake_notebook_entries.py`
  - Add `mistake_notebook_entries` table and indexes.
- Create: `backend-service/tests/test_mistakes_routes.py`
  - Cover create/list/resolve/delete and user isolation.
- Modify: `flutter-app/lib/features/mistakes/data/mistake_notebook_repository.dart`
  - Add sync-aware repository behavior while preserving offline fallback.
- Create: `flutter-app/lib/features/mistakes/data/mistake_notebook_remote_datasource.dart`
  - Call backend API.
- Modify: game, news, and books providers that currently record mistakes locally.

### Phase 3: Unified Pronunciation Coach

- Modify: `flutter-app/lib/features/voice/data/datasources/voice_remote_datasource.dart`
  - Add a backend pronunciation-evaluation call that sends audio and target text.
- Modify: `flutter-app/lib/features/voice/data/repositories/voice_repository_impl.dart`
  - Prefer server HuBERT/phoneme scoring; keep transcript heuristic only as fallback.
- Modify: `flutter-app/lib/features/voice/domain/entities/pronunciation_score.dart`
  - Add phoneme/stress/error metadata if missing.
- Test: `flutter-app/test/features/voice/...`
  - Cover success response, fallback response, and error messaging.

### Phase 4: Server-Side Today Plan

- Create: `backend-service/app/schemas/today_plan.py`
  - Define plan item, priority, reason, destination, completion state.
- Create: `backend-service/app/services/today_plan_service.py`
  - Build plan from due vocabulary, mistakes, proficiency, streak, and available content.
- Create: `backend-service/app/routes/today_plan.py`
  - Authenticated `/today-plan` endpoint.
- Modify: `backend-service/app/main.py`
  - Include router.
- Modify: `flutter-app/lib/features/home/presentation/widgets/home_page/today_plan_models.dart`
  - Use backend plan when available; fallback to local heuristic.
- Test: backend unit tests and Flutter provider/widget tests.

### Phase 5: CEFR And Learning Event Integration

- Modify: `backend-service/app/routes/learning.py`
  - Emit normalized exercise result payloads after answer submission.
- Modify: `backend-service/app/services/proficiency_service.py`
  - Accept learning events from course, game, voice, and content activities.
- Modify: `flutter-app/lib/features/level/presentation/providers/proficiency_provider.dart`
  - Trigger `recordExercises` after lesson/game/content completion where missing.
- Test: backend proficiency tests and Flutter flow tests.

### Phase 6: Premium Entitlements

- Create: `backend-service/app/models/entitlement.py`
  - Store subscription state, provider, product ID, expiration, and last validation timestamp.
- Create: `backend-service/app/routes/entitlements.py`
  - Sync RevenueCat entitlement state and expose current user entitlement.
- Create: `backend-service/app/services/entitlement_service.py`
  - Validate and normalize provider payloads.
- Modify: AI-heavy routes such as chat/pronunciation/TTS/content generation.
  - Enforce free-tier limits and premium access server-side.
- Modify: `flutter-app/lib/core/services/purchases_service.dart`
  - Sync successful purchase/restore state to backend.
- Test: backend route tests, entitlement service tests, and Flutter service tests.

### Phase 7: Analytics, Achievements, And Admin Visibility

- Modify: `backend-service/app/services/achievement_checker_service.py`
  - Replace placeholder stats for voice, writing, listening, and time spent.
- Modify: `backend-service/app/routes/analytics.py`
  - Replace retention sample data with real event aggregation.
- Modify: `admin-service/src/...`
  - Surface mistake trends, CEFR movement, content quality, and conversion metrics.
- Test: backend analytics tests and admin component tests.

### Phase 8: CI And Production Hardening

- Modify: `.github/workflows/ci.yml`
  - Run a broader AI service pytest subset or full AI test suite behind cache/time budget.
- Verify: `backend-service/.gitignore`, root `.gitignore`, and Gitleaks config.
  - Keep service-account JSON, `.env`, generated data, coverage, and local DB artifacts out of git.
- Test: run CI-equivalent commands locally where feasible.

---

## Chunk 1: Replace News Quiz Placeholder

### Task 1: Article-Aware News Quiz Generator

**Files:**

- Modify: `backend-service/app/routes/news.py`
- Modify: `backend-service/tests/test_news_routes.py`

- [x] **Step 1: Add failing tests for non-placeholder quiz output**

Add tests under `TestGenerateQuizStructure`:

```python
@pytest.mark.asyncio
async def test_quiz_uses_article_context_when_available(self):
    from app.routes.news import _generate_quiz

    article = {
        "title": "Solar Panels Power Local School",
        "description": "Students learn from a new renewable energy project.",
        "content": (
            "A local school installed solar panels on the roof. "
            "The project reduces electricity costs and teaches students about renewable energy. "
            "Teachers said the panels will support science lessons throughout the year."
        ),
    }

    quiz = await _generate_quiz("solar_school", article=article)

    serialized = str(quiz).lower()
    assert "solar" in serialized
    assert "renewable" in serialized or "electricity" in serialized
    assert "option a" not in serialized
    assert "ai-generated" not in serialized
```

```python
@pytest.mark.asyncio
async def test_quiz_falls_back_to_article_id_without_placeholders(self):
    from app.routes.news import _generate_quiz

    quiz = await _generate_quiz("climate_policy_2026")

    serialized = str(quiz).lower()
    assert "option a" not in serialized
    assert "ai-generated" not in serialized
    assert quiz["total_questions"] == len(quiz["questions"])
```

- [x] **Step 2: Run the focused failing tests**

Run:

```bash
cd backend-service
./venv/bin/python -m pytest tests/test_news_routes.py::TestGenerateQuizStructure -q
```

Expected before implementation: new tests fail because `_generate_quiz` does not accept `article=` and returns placeholder text.

Actual: failed for the expected reasons before implementation.

- [x] **Step 3: Implement deterministic quiz generation**

Implementation rules:

- Keep `_generate_quiz(article_id: str)` backward compatible by adding `article: dict | None = None`.
- Extract article text from `title`, `description`, and `content`.
- Use simple sentence extraction for detail/comprehension questions.
- Use `_extract_highlight_words(article)` for vocabulary questions.
- Generate grammar question from an article sentence when possible.
- Never return placeholder options such as `Option A` or explanations containing `AI-generated`.
- Return exactly 5 questions, 4 options each, valid `correct_index`, `total_questions`, `xp_reward`.

- [x] **Step 4: Wire route context without extra API cost**

For `GET /news/{article_id}/quiz`, keep existing cache key. Do not add network fetches in this task. This task may only use the article payload if a future caller passes it internally; the route can continue calling `_generate_quiz(article_id)`.

- [x] **Step 5: Run focused news tests**

Run:

```bash
cd backend-service
./venv/bin/python -m pytest tests/test_news_routes.py -q
```

Expected: all news route tests pass.

Actual: `48 passed in 0.35s`.

- [x] **Step 6: Update checklist**

Mark completed steps in this plan after tests pass.

---

## Chunk 2: Synced Mistake Notebook API

### Task 2: Backend Mistake Notebook Foundation

**Files:**

- Create: `backend-service/app/models/mistake.py`
- Create: `backend-service/app/schemas/mistakes.py`
- Create: `backend-service/app/routes/mistakes.py`
- Create: `backend-service/alembic/versions/add_mistake_notebook_entries.py`
- Create: `backend-service/tests/test_mistakes_routes.py`
- Modify: `backend-service/app/main.py`
- Modify: `backend-service/app/models/__init__.py`

- [x] **Step 1: Write model and schema tests first**
- [x] **Step 2: Create SQLAlchemy model**
- [x] **Step 3: Create Alembic migration**
- [x] **Step 4: Create authenticated CRUD routes**
- [x] **Step 5: Include router in `main.py`**
- [x] **Step 6: Run `./venv/bin/python -m pytest tests/test_mistakes_routes.py -q`**
- [x] **Step 7: Run focused backend smoke tests for news quiz and mistake API behavior**

Actual verification:

```bash
cd backend-service
./venv/bin/python -m pytest tests/test_mistakes_routes.py -q
# 4 passed in 29.45s

./venv/bin/python -m pytest tests/test_news_routes.py tests/test_mistakes_routes.py -q
# 55 passed in 71.84s

./venv/bin/alembic heads
# add_mistake_notebook_entries (head)
```

Reviewer-driven hardening:

- Mistake duplicate matching now uses `source_type + source_id + question_hash`, not raw indexed question text or selected answer.
- Client-provided review state, review counters, and timestamps are ignored by create/update; review state is server-owned through the review/reopen endpoints.
- Client IDs are restricted to safe non-UUID strings.
- Alembic smoke for the new migration passed by stamping the test DB at `add_game_powerup_items`, upgrading to `add_mistake_notebook_entries`, downgrading one revision, and upgrading again.

Acceptance criteria:

- Users can create, list, resolve, reopen, and delete only their own mistakes.
- Duplicate source/question pairs can increment `attempt_count` instead of creating noisy duplicates.
- API accepts current Flutter mistake fields without losing metadata.

---

## Chunk 3: Flutter Mistake Sync

### Task 3: Offline-First Mistake Notebook Sync

**Files:**

- Create: `flutter-app/lib/features/mistakes/data/mistake_notebook_remote_datasource.dart`
- Modify: `flutter-app/lib/features/mistakes/data/mistake_notebook_repository.dart`
- Modify: `flutter-app/lib/features/mistakes/domain/mistake_notebook_entry.dart`
- Modify: `flutter-app/lib/features/news/presentation/providers/news_provider.dart`
- Modify: `flutter-app/lib/features/books/presentation/providers/book_provider.dart`
- Modify: `flutter-app/lib/features/games/presentation/helpers/game_mistake_recorder.dart`
- Test: `flutter-app/test/features/mistakes/...`

- [x] **Step 1: Write repository tests for offline save, sync success, and sync failure**
- [x] **Step 2: Add remote datasource using existing API/auth client conventions**
- [x] **Step 3: Preserve SharedPreferences as local cache and retry queue**
- [x] **Step 4: Trigger sync after local mistake saves**
- [x] **Step 5: Run `flutter test test/features/mistakes/mistake_notebook_repository_test.dart`**
- [x] **Step 6: Run `flutter analyze`**

Implementation note:

- Existing mistake producers did not need direct edits because `MistakeNotebookRepository` now uses the registered `ApiClient` from DI when available and falls back to local-only mode otherwise.
- Remote failures queue upsert/review/delete operations in SharedPreferences and retry on the next load or mutation.
- Local entries and pending sync operations are scoped by `UserScopeService` to avoid syncing one user's notebook into another account after logout/login.

Actual verification:

```bash
cd flutter-app
flutter test test/features/mistakes/mistake_notebook_repository_test.dart
# All tests passed

flutter test test/features/mistakes/mistake_notebook_repository_test.dart \
  test/features/mistakes/mistake_notebook_remote_datasource_test.dart
# All tests passed

flutter test test/features/mistakes/mistake_notebook_repository_test.dart \
  test/features/news/presentation/providers/news_provider_mistakes_test.dart \
  test/features/games/presentation/helpers/game_mistake_recorder_test.dart
# All tests passed

flutter analyze
# No issues found! (ran in 43.5s)
```

Reviewer-driven hardening:

- Pending remote operations are scoped by active user and are not flushed under a different user scope.
- Pending delete/review/upsert IDs suppress stale remote merge until the pending operation succeeds.
- Remote datasource paginates `/mistakes` with `limit=100` and `offset`.
- Path IDs are URL-encoded for review/reopen/delete calls.
- API logging now redacts request/response bodies for `/mistakes` and redacts authorization headers.

Known follow-up:

- Pending mistake ops still use SharedPreferences, now scoped and log-redacted. Move this queue to the existing encrypted/background queue infrastructure in a later hardening task.

Acceptance criteria:

- Existing offline behavior still works.
- Logged-in users get cross-device mistake notebook state.
- Failed sync does not lose local entries.

---

## Chunk 4: Unified Pronunciation

### Task 4: Use HuBERT Pronunciation Scoring In Voice Practice

**Files:**

- Modify: `flutter-app/lib/features/voice/data/datasources/voice_remote_datasource.dart`
- Modify: `flutter-app/lib/features/voice/data/repositories/voice_repository_impl.dart`
- Modify: `flutter-app/lib/features/voice/domain/entities/pronunciation_score.dart`
- Test: `flutter-app/test/features/voice/...`

- [ ] **Step 1: Write tests proving HuBERT response is preferred over transcript heuristic**
- [ ] **Step 2: Add remote call to backend pronunciation endpoint**
- [ ] **Step 3: Map phoneme scores and error details to domain entity**
- [ ] **Step 4: Keep transcript heuristic as explicit fallback**
- [ ] **Step 5: Run voice tests and `flutter analyze`**

Acceptance criteria:

- Voice practice can display phoneme-level feedback when backend returns it.
- Offline/API-failure scenarios still produce a basic score.

---

## Chunk 5: Server-Side Today Plan

### Task 5: Personalized Today Plan API

**Files:**

- Create: `backend-service/app/schemas/today_plan.py`
- Create: `backend-service/app/services/today_plan_service.py`
- Create: `backend-service/app/routes/today_plan.py`
- Create: `backend-service/tests/test_today_plan_service.py`
- Modify: `backend-service/app/main.py`
- Modify: Flutter home today-plan provider/model files after API is available.

- [ ] **Step 1: Write service tests for due vocab, mistakes, weak skills, and streak cases**
- [ ] **Step 2: Implement backend planner without AI dependency**
- [ ] **Step 3: Expose authenticated route**
- [ ] **Step 4: Wire Flutter to use backend plan with local fallback**
- [ ] **Step 5: Run backend and Flutter focused tests**

Acceptance criteria:

- Plan explains why each item is recommended.
- Plan has stable IDs and completion states.
- Flutter still works when backend plan is unavailable.

---

## Chunk 6: CEFR Event Wiring

### Task 6: Record Learning Events Into Proficiency Profile

**Files:**

- Modify: `backend-service/app/routes/learning.py`
- Modify: `backend-service/app/services/proficiency_service.py`
- Modify: `flutter-app/lib/features/level/presentation/providers/proficiency_provider.dart`
- Modify: lesson/game/content completion providers as needed.
- Test: backend proficiency tests and Flutter flow tests.

- [ ] **Step 1: Identify every completion flow that produces scoreable exercise results**
- [ ] **Step 2: Add tests for one course lesson, one game, and one content quiz**
- [ ] **Step 3: Normalize result payloads**
- [ ] **Step 4: Call proficiency recording after completion**
- [ ] **Step 5: Run focused tests**

Acceptance criteria:

- CEFR profile changes after real learning activity.
- Duplicate completions do not inflate progress.

---

## Chunk 7: Premium Enforcement

### Task 7: Backend Entitlements And Premium API Guards

**Files:**

- Create: `backend-service/app/models/entitlement.py`
- Create: `backend-service/app/schemas/entitlements.py`
- Create: `backend-service/app/services/entitlement_service.py`
- Create: `backend-service/app/routes/entitlements.py`
- Create: `backend-service/alembic/versions/add_entitlements.py`
- Modify: `backend-service/app/main.py`
- Modify: premium AI/content routes selected for enforcement.
- Modify: `flutter-app/lib/core/services/purchases_service.dart`

- [ ] **Step 1: Write entitlement service tests**
- [ ] **Step 2: Store normalized subscription state**
- [ ] **Step 3: Add sync endpoint and current-entitlement endpoint**
- [ ] **Step 4: Add guards around premium server features**
- [ ] **Step 5: Sync purchase and restore from Flutter**
- [ ] **Step 6: Run backend tests and `flutter analyze`**

Acceptance criteria:

- Premium access cannot be bypassed by editing Flutter state.
- Free users receive clear limit/upgrade responses.

---

## Chunk 8: Analytics And CI Completion

### Task 8: Replace Placeholder Analytics And Broaden AI CI

**Files:**

- Modify: `backend-service/app/routes/analytics.py`
- Modify: `backend-service/app/services/achievement_checker_service.py`
- Modify: `.github/workflows/ci.yml`
- Modify: admin analytics pages after backend metrics exist.

- [ ] **Step 1: Write backend analytics tests for retention and skill activity**
- [ ] **Step 2: Replace retention sample data with DB aggregation**
- [ ] **Step 3: Replace achievement placeholder stats**
- [ ] **Step 4: Add an AI service CI test matrix that is broad but time-bounded**
- [ ] **Step 5: Run backend focused tests and validate workflow syntax**

Acceptance criteria:

- Admin analytics are based on persisted activity.
- CI catches more AI regressions without making every PR painfully slow.

---

## Operating Checklist

- [ ] Query `code-review-graph` before each new implementation chunk.
- [ ] Use TDD for each task: failing test, implementation, passing test.
- [ ] Spawn or simulate `test-writer` review after feature implementations where local tooling allows it.
- [ ] Spawn or simulate `security-reviewer` for auth, API, DB schema, entitlement, or config changes.
- [ ] Request code review before PR or after each substantial chunk.
- [ ] Do not commit until required tests pass.
- [ ] For backend changes, run focused `pytest`; before commit run broader backend tests when feasible.
- [ ] For Flutter changes, run `flutter analyze` and focused `flutter test`.
- [ ] For admin changes, run package tests/build.
