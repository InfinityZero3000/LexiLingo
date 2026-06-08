# Cross-Platform Theme Reliability Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore immediate, persisted `light`/`dark`/`system` switching on Flutter Web, Android, and iOS, then correct light-only semantic colors in recently changed learner screens.

**Architecture:** Add a device-local `ThemePreferenceStore` backed by the already initialized `SharedPreferences` singleton. Keep `SettingsProvider` as the UI API, but give it an effective theme independent of nullable user settings and make repository persistence secondary. Harden native settings writes with an update-or-create fallback and replace light-only exercise colors with context-derived semantic colors.

**Tech Stack:** Flutter, Provider, SharedPreferences, sqflite, flutter_test, mocktail

---

## Chunk 1: Theme State And Persistence

### Task 1: Device Theme Preference Store

**Files:**
- Create: `flutter-app/lib/core/services/theme_preference_store.dart`
- Create: `flutter-app/test/core/services/theme_preference_store_test.dart`
- Modify: `flutter-app/lib/core/utils/constants.dart`

- [ ] **Step 1: Write failing store tests**

Cover missing values, valid values, malformed values, persistence, and the
ability to distinguish a missing legacy key from an explicit `system` value.

- [ ] **Step 2: Run the focused test**

Run:

```bash
cd flutter-app
flutter test test/core/services/theme_preference_store_test.dart
```

Expected: FAIL because `ThemePreferenceStore` does not exist.

- [ ] **Step 3: Implement the store**

Use the injected `SharedPreferences` instance. Expose `hasPreference`,
`readTheme()`, and `writeTheme(String)`; normalize values to `light`, `dark`,
or `system`.

- [ ] **Step 4: Run the focused test again**

Expected: PASS.

### Task 2: Immediate SettingsProvider Theme State

**Files:**
- Modify: `flutter-app/lib/features/user/presentation/providers/settings_provider.dart`
- Modify: `flutter-app/lib/features/user/di/user_di.dart`
- Create: `flutter-app/test/features/user/presentation/providers/settings_provider_theme_test.dart`

- [ ] **Step 1: Write failing provider tests**

Use a fake settings repository and mocked SharedPreferences. Verify:

- Constructor bootstrap from local preference.
- Correct `ThemeMode` mapping.
- Listener notification occurs before repository completion.
- Legacy settings migrate only when the local key is absent.
- A local preference wins over later settings loads.
- Invalid requests normalize to `system`.
- Repository failure does not roll back the effective theme.

- [ ] **Step 2: Run the focused provider test**

Run:

```bash
cd flutter-app
flutter test test/features/user/presentation/providers/settings_provider_theme_test.dart
```

Expected: FAIL against the current nullable-settings implementation.

- [ ] **Step 3: Implement effective theme state**

Inject `ThemePreferenceStore`, initialize `_theme` synchronously, make
`theme`/`themeMode` read it, and update `_theme` before awaiting persistence.
During `loadSettings`, migrate a valid legacy value only when the local key is
missing. Preserve the effective theme when local or repository persistence
fails.

- [ ] **Step 4: Register the dependency**

Register one `ThemePreferenceStore` using the existing `SharedPreferences`
singleton and pass it into the `SettingsProvider` factory.

- [ ] **Step 5: Run provider and store tests**

Expected: PASS.

### Task 3: Native Settings Upsert

**Files:**
- Modify: `flutter-app/lib/features/user/data/datasources/settings_local_data_source.dart`
- Create: `flutter-app/test/features/user/data/datasources/settings_local_data_source_test.dart`

- [ ] **Step 1: Write a failing zero-row update test**

Verify `updateSettings` inserts the model when SQLite reports zero updated
rows, while preserving the normal update path.

- [ ] **Step 2: Run the focused data-source test**

Expected: FAIL because the current method returns zero without creating.

- [ ] **Step 3: Implement update-or-create**

Capture the update count. Return it when positive; otherwise call
`createSettings` and return its result.

- [ ] **Step 4: Run the focused data-source test**

Expected: PASS.

### Task 4: Settings Selector Integration

**Files:**
- Modify: `flutter-app/lib/features/user/presentation/pages/settings_page.dart`
- Create: `flutter-app/test/features/user/presentation/pages/settings_theme_selector_test.dart`

- [ ] **Step 1: Write a failing interaction test**

Pump the selector below a `MaterialApp` and provider. Tap each option and
verify selected state plus effective brightness/mode changes.

- [ ] **Step 2: Make the selector testable and accessible**

Add stable semantic keys to each option, await `updateTheme`, and keep the
entire option area pointer/keyboard accessible.

- [ ] **Step 3: Run the selector test**

Expected: PASS for `light`, `dark`, and `system`.

## Chunk 2: Light/Dark Semantic Color Audit

### Task 5: Premium Exercise Palette

**Files:**
- Modify: `flutter-app/lib/features/learning/presentation/widgets/premium_exercise_widgets.dart`
- Modify: `flutter-app/test/features/learning/dialogue_completion_widget_test.dart`
- Create: `flutter-app/test/features/learning/premium_exercise_theme_test.dart`

- [ ] **Step 1: Add representative light/dark widget tests**

Cover answer cards, prompt surfaces, borders, primary text, secondary text,
muted text, and disabled states. Assert that dark mode does not retain the
light-only white card or dark text colors.

- [ ] **Step 2: Introduce a context-derived semantic palette**

Resolve card, elevated surface, subtle surface, border, primary text,
secondary text, muted text, shadow, and primary accent from `ThemeData`,
`AppColorRoles`, and existing `AppColors`.

- [ ] **Step 3: Replace semantic uses of light-only constants**

Keep fixed feedback colors and white foregrounds where they sit on saturated
backgrounds. Do not alter exercise behavior.

- [ ] **Step 4: Run learning widget tests**

Expected: PASS in both themes.

### Task 6: Recently Changed Screen Audit

**Files:**
- Modify as required:
  - `flutter-app/lib/features/learning/presentation/screens/learning_session_screen.dart`
  - `flutter-app/lib/features/course/presentation/screens/course_list_screen.dart`
  - `flutter-app/lib/features/course/presentation/screens/category_detail_screen.dart`
  - `flutter-app/lib/features/course/presentation/screens/course_detail_screen.dart`
  - `flutter-app/lib/features/chat/presentation/pages/topic_chat_page.dart`
  - `flutter-app/lib/features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart`
  - `flutter-app/lib/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart`
  - `flutter-app/lib/features/lexi_chat/presentation/widgets/lexi_typing_indicator.dart`
  - `flutter-app/lib/features/youtube/presentation/screens/youtube_explore_screen.dart`

- [ ] **Step 1: Classify hard-coded colors**

Separate semantic UI colors from intentional content, status, avatar, badge,
and image-overlay colors.

- [ ] **Step 2: Replace confirmed semantic color regressions**

Use `Theme.of(context).colorScheme`, text themes, and existing app roles. Keep
changes local and avoid unrelated layout or behavior edits.

- [ ] **Step 3: Add or extend focused tests for changed behavior**

Prefer existing screen/widget tests. Add only tests that guard a confirmed
dark/light regression.

## Chunk 3: Verification

### Task 7: Automated Verification

**Files:**
- Modify only files needed to fix discovered failures.

- [ ] **Step 1: Format changed Dart files**

```bash
cd flutter-app
dart format lib/core/services/theme_preference_store.dart lib/core/utils/constants.dart lib/features/user test/core/services/theme_preference_store_test.dart test/features/user test/features/learning
```

- [ ] **Step 2: Run focused theme tests**

```bash
cd flutter-app
flutter test test/core/services/theme_preference_store_test.dart test/features/user test/features/learning/premium_exercise_theme_test.dart
```

- [ ] **Step 3: Run existing affected feature tests**

```bash
cd flutter-app
flutter test test/features/learning test/features/course test/features/chat test/features/lexi_chat
```

- [ ] **Step 4: Run static analysis**

```bash
cd flutter-app
flutter analyze
```

Expected: no new analyzer errors or warnings caused by this change.

- [ ] **Step 5: Review the final diff**

Confirm no unrelated user changes were reverted and report any remaining
out-of-scope theme debt with file references.
