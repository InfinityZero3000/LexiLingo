# Course Detail Thumbnail Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the same resolved course-card image on the course detail hero.

**Architecture:** Course list surfaces resolve their existing display image and
pass it as optional navigation context. The detail screen combines the API
thumbnail and navigation thumbnail into an ordered candidate list rendered by
a cached image widget with a final placeholder.

**Tech Stack:** Flutter, Dart, Provider, cached_network_image, flutter_test

---

## Chunk 1: Course thumbnail handoff

### Task 1: Add deterministic image candidate selection

**Files:**
- Modify: `flutter-app/lib/features/course/presentation/screens/course_detail_screen.dart`
- Test: `flutter-app/test/features/course/course_detail_thumbnail_test.dart`

- [x] Add a pure helper that returns non-empty, unique image candidates in API
  then navigation order.
- [x] Add tests for API priority, navigation fallback, blank values, and
  duplicate removal.
- [x] Run the focused test and confirm it passes.

### Task 2: Pass the displayed card image to detail

**Files:**
- Modify: `flutter-app/lib/features/course/presentation/screens/course_list_screen.dart`
- Modify: `flutter-app/lib/features/course/presentation/screens/category_detail_screen.dart`

- [x] Reuse each screen's existing deterministic image resolver.
- [x] Pass the resolved URL to `CourseDetailScreen`.
- [x] Keep existing Hero tags unchanged.

### Task 3: Render the fallback chain

**Files:**
- Modify: `flutter-app/lib/features/course/presentation/screens/course_detail_screen.dart`

- [x] Add optional `initialThumbnailUrl` constructor input.
- [x] Render image candidates with `CachedNetworkImage`.
- [x] Preserve the current gradient overlay and final placeholder.
- [x] Run format, focused tests, and `flutter analyze`.
