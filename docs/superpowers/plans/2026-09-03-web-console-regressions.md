# Web Console Regressions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Flutter web location exception and broken course-thumbnail requests, then verify the existing vocabulary-review transaction fix.

**Architecture:** Keep each fix at its shared source: use Geolocator for location permission on every platform, replace the dead fallback URL in every live catalog copy, and keep `update_user_streak` aware of pending SQLAlchemy rows when production autoflush is disabled. No new dependency or schema change.

**Tech Stack:** Flutter/Dart, `geolocator`, FastAPI, SQLAlchemy, PostgreSQL, pytest.

---

## Chunk 1: Flutter web console errors

### Task 1: Location permission

**Files:**
- Modify: `flutter-app/lib/features/social/presentation/providers/social_provider.dart`

- [ ] Remove the `permission_handler` call from the nearby-user flow.
- [ ] Use `Geolocator.checkPermission()` and request only when denied.
- [ ] Treat `denied` and `deniedForever` as unavailable; keep the existing user-facing error path.
- [ ] Run `flutter analyze` on the changed provider.

### Task 2: Broken course fallback image

**Files:**
- Modify: `flutter-app/lib/features/course/presentation/utils/course_thumbnail_resolver.dart`
- Modify: `flutter-app/lib/features/course/presentation/screens/course_list_screen.dart`
- Modify: `flutter-app/lib/features/course/presentation/screens/category_detail_screen.dart`
- Test: `flutter-app/test/features/course/course_thumbnail_resolver_test.dart`

- [ ] Add a regression assertion that the removed Unsplash photo ID is never selected.
- [ ] Confirm the assertion fails before the URL replacement.
- [ ] Replace `photo-1523050854058-8df90110c9f1` with the verified HTTP-200 education image `photo-1524178232363-1fb2b075b655` in all three catalogs.
- [ ] Run the resolver test and targeted Flutter analysis.

## Chunk 2: Vocabulary review 500

### Task 3: Production transaction parity

**Files:**
- Modify: `backend-service/app/services/streak_service.py`
- Test: `backend-service/tests/test_streak_service.py`
- Test: `backend-service/tests/integration/test_vocabulary_learner_concept_state.py`

- [ ] Keep the shared service lookup of matching `DailyActivity` objects already staged in `db.new`.
- [ ] Run the service and endpoint regressions with autoflush disabled.
- [ ] Confirm the production request-ID failure (`idx_daily_activity_user_date` followed by `PendingRollbackError`) is covered.

## Chunk 3: Verification

- [ ] Run targeted Flutter tests and `flutter analyze`.
- [ ] Run targeted backend pytest suites with PostgreSQL.
- [ ] Run `git diff --check` and review only task-owned files.
- [ ] Do not commit or deploy from this dirty worktree; report the required deployment step separately.
