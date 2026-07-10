# LexiLingo App I18N Global Guide

## Goal
Use English as the global source of truth for all app text, keep every locale file shape-identical, and make language switching safe across the Flutter app without missing keys, mixed-language UI, or broken layouts.

## Source Of Truth
- `flutter-app/assets/i18n/en.json` is the canonical baseline.
- Every new key must be added to all 7 supported locale files in the same change:
  - `en.json`
  - `vi.json`
  - `ja.json`
  - `ko.json`
  - `zh.json`
  - `fr.json`
  - `es.json`
- If a locale is not translated yet, use the English value temporarily. Missing keys are not allowed.

## Required Rules For Copilot
- Do not ship new hardcoded user-facing strings in Flutter pages, widgets, dialogs, buttons, snackbars, empty states, titles, or onboarding copy.
- Reuse existing keys first; only create new keys when the wording is actually distinct.
- Keep JSON structure aligned across all locale files. No extra keys in one locale, no missing keys in another.
- Prefer stable, descriptive namespaces such as `auth`, `profile`, `settings`, `course`, `voice`, `social`, `errors`, `common`.
- For partial rollout work, add the key to all locale files first, then refactor UI code to use `.tr()`.
- For untranslated locales, English fallback is preferred over inconsistent machine-translated text or missing keys.

## App-Level Workflow
1. Add or update the English string in `en.json`.
2. Mirror the same key path into the other 6 locale files.
3. Fill translated values where available.
4. Use English fallback text for any locale that is still pending translation.
5. Replace the Flutter hardcoded string with `.tr()`.
6. Validate the touched Flutter slice with analyzer or errors check.

## JSON Shape Policy
- `en.json` defines the master schema.
- Nested objects must exist in all locale files with the same hierarchy.
- Interpolation placeholders must match exactly across locales, for example `{name}`, `{count}`, `{level}`, `{version}`.
- Do not rename or repurpose an existing key without updating all locales and all call sites.

## Translation Policy
- English is the product's global baseline language.
- Vietnamese, Japanese, Korean, Chinese, French, and Spanish must never be allowed to drift structurally from English.
- When translation quality is uncertain, keep English text instead of inventing inconsistent wording.
- Avoid expanding text with unnecessary punctuation or extra explanatory sentences that can break layouts in one locale only.

## Runtime Policy
- Global language switching must always rely on shared locale state, not per-screen toggles.
- Settings-backed language and pre-auth language changes must update the same locale pipeline.
- If a screen appears unchanged after locale switching, first check for hardcoded strings before suspecting the locale engine.

## Current Sweep Strategy
Sweep hardcoded text by clusters so each batch is easy to validate.

### Cluster 1: Auth Entry
- `flutter-app/lib/features/auth/presentation/pages/login_page.dart`
- `flutter-app/lib/features/auth/presentation/pages/register_page.dart`
- `flutter-app/lib/features/auth/presentation/pages/forgot_password_page.dart`
- `flutter-app/lib/features/auth/presentation/pages/reset_password_page.dart`
- `flutter-app/lib/features/auth/presentation/pages/welcome_page.dart`
- `flutter-app/lib/features/auth/presentation/pages/pre_auth_questions_page.dart`
- `flutter-app/lib/features/auth/presentation/widgets/auth_wrapper.dart`

### Cluster 2: Profile And Account
- `flutter-app/lib/features/profile/presentation/pages/profile_page.dart`
- `flutter-app/lib/features/profile/presentation/pages/edit_profile_screen.dart`
- `flutter-app/lib/features/user/presentation/pages/settings_page.dart`

### Cluster 3: Learning Core
- `flutter-app/lib/features/learning/presentation/screens/learning_session_screen.dart`
- `flutter-app/lib/features/vocabulary/presentation/screens/flashcard_review_screen.dart`
- `flutter-app/lib/features/progress/presentation/screens/my_progress_screen.dart`
- `flutter-app/lib/features/voice/presentation/screens/voice_practice_screen.dart`

### Cluster 4: Social And Gamification
- `flutter-app/lib/features/social/presentation/screens/social_screen.dart`
- `flutter-app/lib/features/gamification/presentation/screens/shop_screen.dart`
- `flutter-app/lib/features/gamification/presentation/screens/leaderboard_screen.dart`
- `flutter-app/lib/features/achievements/presentation/screens/achievements_screen.dart`

### Cluster 5: Content Surfaces
- `flutter-app/lib/features/news/presentation/screens/news_quiz_screen.dart`
- `flutter-app/lib/features/course/presentation/screens/course_detail_screen.dart`
- `flutter-app/lib/features/youtube/presentation/screens/youtube_player_screen.dart`
- `flutter-app/lib/features/books/presentation/screens/book_reader_screen.dart`

## Known Resource Gaps Closed In This Pass
- Japanese and Korean must be kept shape-identical with English even where translation is incomplete.
- New shared keys should be added to all locale files before sweeping the next hardcoded cluster.

## Acceptance Standard
Language switching is considered healthy only when:
- locale state changes globally,
- visible shell/auth/profile/settings surfaces react immediately,
- all 7 locale files contain the same key set,
- untranslated text falls back to English instead of disappearing,
- no major user-facing screen cluster still depends on hardcoded English literals.