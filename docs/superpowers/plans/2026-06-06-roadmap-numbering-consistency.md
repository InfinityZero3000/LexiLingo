# Roadmap Numbering Consistency Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make unit and lesson numbering consistent between course detail and the full learning roadmap.

**Architecture:** Keep `order_index` as the persisted sorting key. Build one-based display ordinals from the sorted collections in the learning roadmap endpoint, and use the previous sorted lesson for progression locking.

**Tech Stack:** Python, FastAPI, SQLAlchemy, pytest, Flutter/Dart consumer models

---

## Chunk 1: Backend Normalization

### Task 1: Add Roadmap Numbering Regression Coverage

**Files:**
- Modify: `backend-service/tests/test_learning_routes.py`

- [x] Assert unit numbers equal `1..N` in returned order.
- [x] Assert lesson numbers equal `1..N` within every returned unit.
- [x] Run the focused roadmap tests and confirm the old implementation fails
      for one-based fixture data.

### Task 2: Normalize Roadmap Display Order

**Files:**
- Modify: `backend-service/app/routes/learning.py`
- Test: `backend-service/tests/test_learning_routes.py`

- [x] Sort units once and enumerate them from 1.
- [x] Sort each unit's lessons once and enumerate them from 1.
- [x] Determine locking from the previous sorted lesson.
- [x] Preserve titles, descriptions, colors, progress, and totals.
- [ ] Run focused backend tests (blocked locally: `lexilingo_test` database is
      not configured).

### Task 3: Verify Flutter Compatibility

**Files:**
- Verify: `flutter-app/lib/features/course/presentation/screens/course_detail_screen.dart`
- Verify: `flutter-app/lib/features/learning/data/models/roadmap_model.dart`
- Verify: `flutter-app/lib/features/learning/presentation/screens/learning_roadmap_screen.dart`

- [x] Confirm both screens render one-based ordinals.
- [x] Run Flutter analysis for the affected files.
- [x] Review the final diff for unrelated changes.
