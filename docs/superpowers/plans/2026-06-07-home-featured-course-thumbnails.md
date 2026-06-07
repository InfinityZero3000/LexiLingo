# Home Featured Course Thumbnails Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display deterministic course cover images in Home featured-course cards.

**Architecture:** Move the existing tag/level/ID fallback selection into a pure shared helper. Course and Home presentation widgets consume the helper, while Home uses `CachedNetworkImage` to fall back from the backend thumbnail to the computed image and finally to its current placeholder.

**Tech Stack:** Flutter, Dart, cached_network_image, flutter_test

---

## Chunk 1: Shared thumbnail resolution

### Task 1: Extract and test the fallback resolver

**Files:**
- Create: `flutter-app/lib/features/course/presentation/utils/course_thumbnail_resolver.dart`
- Create: `flutter-app/test/features/course/course_thumbnail_resolver_test.dart`
- Modify: `flutter-app/lib/features/course/presentation/screens/course_list_screen.dart`
- Modify: `flutter-app/lib/features/course/presentation/screens/category_detail_screen.dart`

- [x] Add tests for tag selection, level selection, deterministic ID selection,
  and backend/fallback candidate ordering.
- [x] Add a pure shared resolver containing the existing Course image catalog
  and selection rules.
- [x] Reuse the shared helper from the Home course surface.
- [x] Run the focused resolver tests.

### Task 2: Render fallback images on Home

**Files:**
- Modify: `flutter-app/lib/features/home/presentation/pages/home_page.dart`

- [x] Import `cached_network_image` and the shared resolver.
- [x] Render backend and computed image candidates with automatic error fallback.
- [x] Preserve the gradient, badges, Hero tag, card dimensions, and final
  school-icon placeholder.
- [x] Pass the same thumbnail candidates into the course detail Hero.
- [x] Run Dart formatting, focused tests, and `flutter analyze`.
