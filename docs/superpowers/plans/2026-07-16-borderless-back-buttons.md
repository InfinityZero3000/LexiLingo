# Borderless Back Buttons Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the black circular border from every Flutter button that exits the current screen or dialog.

**Architecture:** Add one small `AppBackButton` wrapper around `IconButton`, with a borderless local style that overrides the learner theme. Migrate only route/dialog Back controls; keep all other circular icon controls unchanged.

**Tech Stack:** Flutter, Material, flutter_test

---

## Chunk 1: Shared button

### Task 1: Add and verify `AppBackButton`

**Files:**
- Create: `flutter-app/lib/core/widgets/app_back_button.dart`
- Create: `flutter-app/test/core/widgets/app_back_button_test.dart`

- [x] Write widget tests for no border, 48x48 minimum target, tooltip, custom callback, and default `Navigator.maybePop`.
- [x] Run `flutter test test/core/widgets/app_back_button_test.dart`; expect failure because the widget does not exist.
- [x] Implement `AppBackButton` using `IconButton`, `BorderSide.none`, transparent background, optional icon/color/callback, and localized/fallback Back tooltip.
- [x] Run the focused test; expect PASS.

## Chunk 2: Route Back migration

### Task 2: Replace learner route/dialog Back controls

**Files:**
- Modify: `flutter-app/lib/features/auth/presentation/pages/login_page.dart`
- Modify: `flutter-app/lib/features/auth/presentation/pages/register_page.dart`
- Modify: `flutter-app/lib/features/books/presentation/screens/book_detail_screen.dart`
- Modify: `flutter-app/lib/features/books/presentation/screens/book_reader_screen.dart`
- Modify: `flutter-app/lib/features/chat/presentation/pages/topic_chat_page.dart`
- Modify: `flutter-app/lib/features/home/presentation/pages/today_plan_page.dart`
- Modify: `flutter-app/lib/features/learning/presentation/widgets/roadmap_header_widget.dart`
- Modify: `flutter-app/lib/features/news/presentation/screens/news_detail_screen.dart`
- Modify: `flutter-app/lib/features/news/presentation/screens/news_list_screen.dart`
- Modify: `flutter-app/lib/features/notifications/presentation/pages/notifications_page.dart`
- Modify: `flutter-app/lib/features/podcast/presentation/screens/podcast_explore_screen.dart`
- Modify: `flutter-app/lib/features/profile/presentation/pages/edit_profile_screen.dart`
- Modify: `flutter-app/lib/features/progress/presentation/widgets/points_calendar_dialog.dart`
- Modify: `flutter-app/lib/features/user/presentation/pages/legal_page.dart`
- Modify: `flutter-app/lib/features/user/presentation/pages/settings_page.dart`
- Modify: `flutter-app/lib/features/vocabulary/presentation/pages/vocab_library_page.dart`
- Modify: `flutter-app/lib/features/youtube/presentation/screens/youtube_explore_screen.dart`
- Modify: `flutter-app/lib/features/youtube/presentation/screens/youtube_player_screen.dart`

- [x] Inventory with `rg -n -C 4 "Icons\\.(arrow_back|arrow_back_ios|arrow_back_ios_new|chevron_left)(_rounded)?|BackButton\\(" flutter-app/lib/features --glob '*.dart'`; qualify controls that close/replace the current screen or dismiss a dialog.
- [x] Replace every qualifying route/dialog Back control with `AppBackButton`, including `IconButton`, `BackButton`, `GestureDetector`, and custom circular wrappers; preserve its icon, color, callback, and tooltip semantics.
- [x] Remove only now-unused imports or local button decoration.
- [x] Explicitly exclude pre-auth previous-question, placement-test previous-step, calendar previous-month, media skip-back, YouTube search reset, and labeled TextButton/OutlinedButton actions.
- [x] Re-run the inventory command; manually confirm remaining matches are those explicit exclusions.

### Task 3: Replace admin route Back controls

**Files:**
- Modify: `flutter-app/lib/features/admin/features/auth/presentation/otp_screen.dart`
- Modify: `flutter-app/lib/features/admin/features/curriculum/presentation/course_detail_screen.dart`
- Modify: `flutter-app/lib/features/admin/features/curriculum/presentation/units_lessons_screen.dart`
- Modify: `flutter-app/lib/features/admin/features/super_admin/presentation/super_dashboard_screen.dart`
- Modify: `flutter-app/lib/features/admin/features/super_admin/presentation/system_health_screen.dart`
- Modify: `flutter-app/lib/features/admin/features/users/presentation/user_stats_screen.dart`

- [x] Replace only icon buttons that call `context.pop()` or dismiss the current admin route.
- [x] Preserve admin icon color and callbacks.
- [x] Re-run the inventory search and confirm remaining arrows are labeled navigation actions rather than icon Back controls.

## Chunk 3: Verification

### Task 4: Validate the migration

- [x] Run `flutter test test/core/widgets/app_back_button_test.dart`; expect PASS.
- [x] Run `flutter test`; expect the existing Flutter suite to PASS.
- [x] Run `flutter analyze`; expect no new issues.
- [ ] Run `dart format` on changed Dart files.
- [x] Review the final diff to confirm only Back-button presentation changed.
- [x] Do not commit documentation files; commit code only if explicitly requested.
