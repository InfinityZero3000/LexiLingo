# Language Flag Preload Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warm the supported-language flag cache at app startup and eliminate broken flag image boxes in Settings.

**Architecture:** A focused core service owns flag URL enumeration and best-effort image precaching. The app starts it after the first frame, while Settings consumes the same cached image provider with explicit loading and error states.

**Tech Stack:** Flutter, Dart, `cached_network_image`, Flutter widget tests

---

## Chunk 1: Flag cache and Settings integration

### Task 1: Add shared flag preload service

**Files:**
- Create: `flutter-app/lib/core/services/language_flag_cache.dart`
- Test: `flutter-app/test/core/services/language_flag_cache_test.dart`

- [x] Add a test asserting every supported locale has a preload URL.
- [x] Implement idempotent, best-effort precaching with `CachedNetworkImageProvider`.
- [x] Run the focused test.

### Task 2: Start preload and consume the same cache

**Files:**
- Modify: `flutter-app/lib/main.dart`
- Modify: `flutter-app/lib/features/user/presentation/pages/settings_page.dart`

- [x] Start preload after the first rendered frame without blocking startup.
- [x] Replace page-local all-or-nothing preload state with `CachedNetworkImage`.
- [x] Preserve skeleton and country-code fallback UI.
- [x] Format changed Dart files.
- [x] Run focused tests and `flutter analyze`.
