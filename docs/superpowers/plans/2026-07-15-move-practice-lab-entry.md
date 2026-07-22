# Move Practice Lab Entry Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Practice Lab from Home quick actions and expose it from the Profile app bar in place of Voice Practice.

**Architecture:** Reuse the existing `/practice-lab` named route. Change only the two UI entry points; do not alter Practice Lab or Voice feature internals.

**Tech Stack:** Flutter, Dart, flutter_test

---

## Chunk 1: Navigation Entry Move

### Task 1: Remove the Home entry

**Files:**
- Modify: `flutter-app/lib/features/home/presentation/widgets/home_page/quick_actions_grid.dart`

- [x] Remove the Practice Lab map from `quickActions`.
- [x] Remove its dark-mode palette value and shift the remaining indexes so each action keeps its current color.
- [x] Run `dart format lib/features/home/presentation/widgets/home_page/quick_actions_grid.dart` from `flutter-app`.

### Task 2: Replace the Profile Voice button

**Files:**
- Modify: `flutter-app/lib/features/profile/presentation/pages/profile_page.dart`

- [x] Remove the unused `VoicePracticeScreen` import.
- [x] Change the microphone button to `Icons.science_rounded` with tooltip `Practice Lab`.
- [x] Navigate with `Navigator.pushNamed(context, '/practice-lab')`.
- [x] Run `dart format lib/features/profile/presentation/pages/profile_page.dart` from `flutter-app`.

### Task 3: Verify behavior

**Files:**
- Create: `flutter-app/test/features/navigation/practice_lab_entry_test.dart`

- [x] Add a focused source-regression test that reads the two UI files and asserts:
  - Home contains neither `practiceLab.shortTitle` nor a `/practice-lab` route.
  - Profile contains `Icons.science_rounded`, the `Practice Lab` tooltip, and `Navigator.pushNamed(context, '/practice-lab')`.
  - Profile contains neither `VoicePracticeScreen` nor its import.
- [x] Run `flutter test test/features/navigation/practice_lab_entry_test.dart`; expect all tests to pass.
- [x] Run `flutter analyze`.
- [x] Review the final diff for unrelated changes.
