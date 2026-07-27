# User Surface Style System Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Home tactile card and strong-control-border language to every authenticated learner flow in light and dark mode without changing Admin or pre-auth UI.

**Architecture:** Add one semantic `ThemeExtension`, one learner-scoped `Theme` wrapper, and one learner route helper. Migrate presentation widgets by feature group using a checked-in coverage ledger; standard Material controls inherit scoped styles while custom surfaces request deterministic decorations.

**Tech Stack:** Flutter Material 3, Dart, Provider, `flutter_test`; no new dependency.

**Spec:** `docs/superpowers/specs/2026-07-15-user-surface-style-system-design.md`

---

## Chunk 1: Foundation and Scope

### Task 1: Build the learner coverage ledger

**Files:**
- Create: `docs/ui/learner-tactile-style-inventory.json`
- Test: `test/core/navigation/learner_surface_inventory_test.dart`

- [x] **Step 1: Write the failing ledger-schema guard**

Parse the JSON with `dart:convert`. Its top-level shape is
`{"occurrences": [...], "boundaries": [...]}`. Each occurrence has stable
`id`, exact `path`, `entryPoint` (`namedRoute`, `tab`, `imperativeRoute`,
`overlay`, or `surface`), `symbol`, `callKind`, zero-based `ordinal` within that
symbol/call kind, optional diagnostic `line`, `category`, `group`, `status`, and
`reason` when excluded. IDs are exactly
`path::symbol::callKind::ordinal`; line numbers are never keys. Surface rows
contain `colors.light` and `colors.dark`, each with eight-digit `0xAARRGGBB`
strings for nullable `accent`, `fill`, `pageBackground`, and nullable
`intermediateFill`; conditional colors use separate occurrence rows. Boundary
records instead have `pattern`, `scope`, and non-empty `reason`. Reject duplicate
IDs, unknown enum strings, empty reasons, invalid ARGB, and contrast tuples whose
optional `intermediateFill` still cannot reach `3:1`.

- [x] **Step 2: Run the guard and verify failure**

Run: `flutter test test/core/navigation/learner_surface_inventory_test.dart`
Expected: FAIL because the inventory does not exist.

- [x] **Step 3: Add route and overlay occurrence discovery assertions**

Scan exact occurrences of route-map keys, `Navigator.push`, `pushNamed`,
`MaterialPageRoute`, `showDialog`, `showGeneralDialog`, `showModalBottomSheet`,
and project helpers that call them. Also scan `Card(`, `BoxDecoration(`,
`DecoratedBox(`, and classes whose names end in `Card`, `Tile`, or `Button`;
every occurrence must be categorized or explicitly excluded. Derive enclosing
symbol and deterministic ordinal in source order, then require its exact ledger
ID. Assert the five `MainScreen` tabs and every learner named route individually.
Add fixed excluded boundary patterns for `lib/features/admin/**`,
`lib/features/profile/presentation/widgets/profile_page/admin_panel_tile.dart`,
and each pre-auth entry family; do not recursively classify their internals.
Implement this as a lexical/source scanner using `dart:io` and `RegExp`; do not
import transitive `package:analyzer` or add a dependency.

- [x] **Step 4: Inventory shell/Home, course/learning/practice/level**

Add one row per route, overlay, and eligible/excluded surface occurrence for
groups 1–3, including separate runtime color tuples. Run the guard; expected
failure output lists only groups 4–7 not yet inventoried.

- [x] **Step 5: Inventory content and activity groups**

Add groups 4–5 (news/books/podcast/YouTube and vocabulary/games/voice/chat).
Run the guard; expected failure output lists only group 6–7 occurrences.

- [x] **Step 6: Inventory user utilities and overlays**

Add groups 6–7 and explicit exclusions. For any tuple below `3:1`, set a
concrete `intermediateFill` ARGB value and test the rerun; the guard prints the
row ID and both failed ratios when no valid value exists.

- [x] **Step 7: Run the complete guard**

Run: `flutter test test/core/navigation/learner_surface_inventory_test.dart`
Expected: PASS with no uncovered route/overlay/surface occurrence, invalid
tuple, missing group, or unexplained exclusion.

- [ ] **Step 8: Commit**

```bash
git add docs/ui/learner-tactile-style-inventory.json test/core/navigation/learner_surface_inventory_test.dart
git commit -m "test: inventory learner tactile surfaces"
```

### Task 2: Implement deterministic semantic styles

**Files:**
- Create: `lib/core/theme/app_tactile_theme.dart`
- Create: `test/core/theme/app_tactile_theme_test.dart`

- [ ] **Step 1: Write failing resolver numeric tests**

Test the exact ordered HSL candidates, neutral candidates, opaque conversion,
tie ordering, and contrast ratio. Load every tuple from the JSON ledger. The
resolver throws `ArgumentError` containing both ratios and the ledger tuple ID
when no candidate or `intermediateFill` reaches `3:1`.

- [ ] **Step 2: Write failing decoration-state tests**

Cover border widths (`2.0`, nested `1.5`), default radius `16`, preserved custom
radius, resting `(0,4)`, pressed `(0,1)`, nested/disabled no-shadow, light
accent shadow alpha `0.18`, light neutral black `0.10`, and dark black `0.35`.

- [ ] **Step 3: Write failing control-style and ThemeExtension tests**

Cover filled/outlined/text/icon `ButtonStyle` state resolution, focused border,
disabled colors, plus `copyWith` and `lerp` endpoints.

- [ ] **Step 4: Run tests and verify failure**

Run: `flutter test test/core/theme/app_tactile_theme_test.dart`
Expected: FAIL because `AppTactileTheme` is undefined.

- [ ] **Step 5: Add the minimal API**

Implement:

```dart
enum TactileSurfaceVariant { elevated, interactive, nested }

final class AppTactileTheme extends ThemeExtension<AppTactileTheme> {
  const AppTactileTheme({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.onSurface,
    required this.pageBackground,
  });

  BoxDecoration decoration({
    required TactileSurfaceVariant variant,
    required Color fill,
    Color? accent,
    Color? intermediateFill,
    BorderRadius? borderRadius,
    Set<WidgetState> states = const {},
    String? diagnosticId,
  });

  ButtonStyle filledButtonStyle({Color? accent});
  ButtonStyle outlinedButtonStyle({Color? accent});
  ButtonStyle textButtonStyle({Color? accent});
  ButtonStyle iconButtonStyle({Color? accent});
}
```

Make accents opaque before HSL conversion. If `intermediateFill` is supplied it
becomes the returned decoration color and the contrast reference; otherwise
`fill` is both. A failure throws `ArgumentError` with `diagnosticId`, the winning
candidate, border/effective-fill ratio, and border/page ratio. Add one synthetic
impossible-tuple test independent of the passing ledger tuples.

`copyWith` preserves unspecified fields; `lerp` uses `Color.lerp` and switches
brightness at `t >= .5`. Resolve `base = accent ?? primary`. Control styles use:

| Style/state | Background | Foreground | Side | Overlay/elevation |
|---|---|---|---|---|
| filled rest | `base` | `onPrimary` when no accent, otherwise highest-contrast black/white | resolved `2.0` | elevation `2` |
| filled pressed/focused/hovered | rest | rest | resolved `2.0` | `onSurface` alpha `.12/.12/.08`; elevation `1/2/2` |
| outlined rest | transparent | `base` | resolved `2.0` | elevation `0` |
| outlined pressed/focused/hovered | transparent | `base` | resolved `2.0` | `base` alpha `.12/.12/.08` |
| text rest | transparent | `base` | none | elevation `0` |
| text pressed/focused/hovered | transparent | `base` | focused: resolved `2.0`; otherwise none | `base` alpha `.12/.12/.08` |
| icon rest | transparent | `base` | resolved `2.0` | elevation `0` |
| icon pressed/focused/hovered | transparent | `base` | resolved `2.0` | `base` alpha `.12/.12/.08`; elevation `0` |
| any disabled | `onSurface` alpha `.12` for filled, otherwise transparent | `onSurface` alpha `.38` | `onSurface` alpha `.12` where the style has a side | no overlay/elevation |

Keep contrast calculation private and pure. `LearnerTheme` maps the extension's
`filledButtonStyle` into both `FilledButtonThemeData` and
`ElevatedButtonThemeData`, and the remaining builders into
`OutlinedButtonThemeData`, `TextButtonThemeData`, and `IconButtonThemeData`.
`CardThemeData` uses `colorScheme.surface`, a rounded rectangle with the neutral
resolved `2.0` side and radius `16`, elevation `3`, shadow color black alpha
`.10` in light and `.35` in dark, and transparent `surfaceTintColor`. This is the
native Material approximation; exact zero-blur offset shadows remain available
only through custom semantic decorations.

- [ ] **Step 6: Run focused tests**

Run: `flutter test test/core/theme/app_tactile_theme_test.dart`
Expected: PASS.

- [ ] **Step 7: Run focused analyzer**

Run: `flutter analyze lib/core/theme/app_tactile_theme.dart test/core/theme/app_tactile_theme_test.dart`
Expected: `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add lib/core/theme/app_tactile_theme.dart test/core/theme/app_tactile_theme_test.dart
git commit -m "feat: add semantic tactile surface styles"
```

### Task 3: Scope styles to learner routes

**Files:**
- Create: `lib/core/navigation/learner_route.dart`
- Modify: `lib/core/theme/app_tactile_theme.dart`
- Modify: `lib/main.dart`
- Modify: `lib/features/auth/presentation/widgets/auth_wrapper.dart`
- Test: `test/core/navigation/learner_route_test.dart`

- [ ] **Step 1: Write failing scope tests**

Assert `LearnerRoute.builder` and `LearnerRoute.push` place
`AppTactileTheme` in `Theme.extensions`, configure card/button themes, and keep
route name, arguments, fullscreen-dialog flag, generic pop result, and native
`MaterialPageRoute` transitions. Mount minimal probes outside `LearnerTheme`
under both global themes and assert the extension is absent and baseline card,
filled, outlined, text, and icon theme fields are unchanged.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/core/navigation/learner_route_test.dart`
Expected: FAIL because the helper is undefined.

- [ ] **Step 3: Implement route wrapper**

Add `LearnerTheme` to `app_tactile_theme.dart`. Add these APIs to the routing
file:

```dart
typedef LearnerWidgetBuilder = Widget Function(BuildContext context);

static WidgetBuilder builder(LearnerWidgetBuilder child);
static Future<T?> push<T>(
  BuildContext context,
  LearnerWidgetBuilder child, {
  RouteSettings? settings,
  bool fullscreenDialog = false,
});

static Future<T?> pushReplacement<T, TO>(
  BuildContext context,
  LearnerWidgetBuilder child, {
  TO? result,
  RouteSettings? settings,
  bool fullscreenDialog = false,
});
```

`push` delegates to `Navigator.push<T>` with a `MaterialPageRoute<T>` whose
builder returns `LearnerTheme(child: child(context))`. In `AuthWrapper`, wrap
only the authenticated `MainScreen` branch; onboarding and loading/pre-auth
branches remain global. In `main.dart`, wrap exactly `/youtube`,
`/youtube/player`, `/news`, `/news/detail`, `/news/quiz`, `/games`, `/courses`,
`/today-plan`, `/practice-lab`, `/mistake-notebook`, `/profile`,
`/achievements`, `/social`, `/premium`, `/offline-sync`, `/placement-test`,
`/vocabulary/review`, `/vocabulary/word-of-day`, `/podcast`, `/podcast/detail`,
`/podcast/player`, `/books`, and `/lexi`. Do not wrap `/reset-password`.
`pushReplacement` delegates to `Navigator.pushReplacement<T, TO>` with the same
wrapper and preserves the replacement result; cover it in the route tests.

- [ ] **Step 4: Run scope tests and analyzer**

Run: `flutter test test/core/navigation/learner_route_test.dart && flutter analyze lib/core/navigation/learner_route.dart lib/core/theme/app_tactile_theme.dart lib/main.dart lib/features/auth/presentation/widgets/auth_wrapper.dart`
Expected: PASS and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/core/navigation/learner_route.dart lib/core/theme/app_tactile_theme.dart lib/main.dart lib/features/auth/presentation/widgets/auth_wrapper.dart test/core/navigation/learner_route_test.dart
git commit -m "feat: scope tactile theme to learner routes"
```

### Task 4: Run the Chunk 1 gate

**Files:** None.

- [ ] **Step 1: Run all foundation tests together**

Run: `flutter test test/core/navigation/learner_surface_inventory_test.dart test/core/theme/app_tactile_theme_test.dart test/core/navigation/learner_route_test.dart`
Expected: PASS.

- [ ] **Step 2: Run the full analyzer**

Run: `flutter analyze`
Expected: `No issues found!`.

---

## Chunk 2: Core Learner Experience

### Task 5: Migrate Home and shared controls

**Files:**
- Modify: `docs/ui/learner-tactile-style-inventory.json`
- Modify: `lib/core/widgets/app_button.dart`
- Modify: `lib/features/home/presentation/widgets/home_ui_components.dart`
- Modify: `lib/features/home/presentation/pages/home_page.dart`
- Modify: `lib/features/home/presentation/pages/main_screen.dart`
- Modify: `lib/features/home/presentation/pages/today_plan_page.dart`
- Modify: `lib/features/home/presentation/widgets/home_page/quick_actions_grid.dart`
- Modify: `lib/features/home/presentation/widgets/home_page/today_plan_section.dart`
- Modify: `lib/features/home/presentation/widgets/home_page/enrolled_courses_section.dart`
- Modify: `lib/features/home/presentation/widgets/home_page/featured_courses_section.dart`
- Modify: `lib/features/home/presentation/widgets/home_page/level_and_daily_goal_row.dart`
- Modify: `lib/features/home/presentation/widgets/home_page/streak_card_section.dart`
- Modify: `lib/features/home/presentation/widgets/home_page/today_plan_navigation.dart`
- Create: `test/helpers/learner_theme_harness.dart`
- Create: `test/core/widgets/app_button_tactile_style_test.dart`
- Test: `test/features/home/home_tactile_style_test.dart`

- [ ] **Step 1: Write representative light/dark widget tests**

Create a harness with `MaterialApp`, `LearnerTheme`, EasyLocalization delegates,
and only required fake providers. Assert the public Home streak, quick action,
Today's Plan, and course-card widgets use semantic values. Drive pressed state
with `tester.startGesture`/`up` and focus with `FocusNode`. Test AppButton's
resting/focused/pressed/disabled styles separately under `test/core/widgets`.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/core/widgets/app_button_tactile_style_test.dart test/features/home/home_tactile_style_test.dart`
Expected: FAIL on legacy inline decorations.

- [ ] **Step 3: Migrate shared button and Home summaries**

Migrate `app_button.dart`, `home_ui_components.dart`,
`streak_card_section.dart`, and `today_plan_section.dart`; close their ledger
IDs and run both style tests.

- [ ] **Step 4: Migrate discovery/course Home surfaces**

Migrate `quick_actions_grid.dart`, `enrolled_courses_section.dart`,
`featured_courses_section.dart`, and `level_and_daily_goal_row.dart`. Preserve
feature fill/accent/radius and provider behavior; run the Home style test.

- [ ] **Step 5: Migrate Home pages and imperative routes**

Migrate `home_page.dart`, `main_screen.dart`, `today_plan_page.dart`, and
`today_plan_navigation.dart`. Convert its CourseList and VoicePractice pushes to
`LearnerRoute.push`, assert destination types, and close remaining Home rows.

- [ ] **Step 6: Verify Home and ledger**

Run: `flutter test test/core/widgets/app_button_tactile_style_test.dart test/features/home/home_tactile_style_test.dart test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart && flutter analyze`
Expected: PASS and no analyzer issues.

- [ ] **Step 7: Commit exact files**

```bash
git add docs/ui/learner-tactile-style-inventory.json lib/core/widgets/app_button.dart lib/features/home/presentation/widgets/home_ui_components.dart lib/features/home/presentation/pages/home_page.dart lib/features/home/presentation/pages/main_screen.dart lib/features/home/presentation/pages/today_plan_page.dart lib/features/home/presentation/widgets/home_page/quick_actions_grid.dart lib/features/home/presentation/widgets/home_page/today_plan_section.dart lib/features/home/presentation/widgets/home_page/enrolled_courses_section.dart lib/features/home/presentation/widgets/home_page/featured_courses_section.dart lib/features/home/presentation/widgets/home_page/level_and_daily_goal_row.dart lib/features/home/presentation/widgets/home_page/streak_card_section.dart lib/features/home/presentation/widgets/home_page/today_plan_navigation.dart test/helpers/learner_theme_harness.dart test/core/widgets/app_button_tactile_style_test.dart test/features/home/home_tactile_style_test.dart
git commit -m "feat: align home with tactile surface system"
```

### Task 6: Migrate learning, course, practice, and level flows

**Files:**
- Modify: `docs/ui/learner-tactile-style-inventory.json`
- Modify: `lib/features/course/presentation/screens/course_list_screen.dart`
- Modify: `lib/features/course/presentation/screens/category_detail_screen.dart`
- Modify: `lib/features/course/presentation/screens/course_detail_screen.dart`
- Modify: `lib/features/learning/presentation/screens/learning_roadmap_screen.dart`
- Modify: `lib/features/learning/presentation/screens/learning_session_screen.dart`
- Modify: `lib/features/learning/presentation/widgets/lesson_content_widget.dart`
- Modify: `lib/features/learning/presentation/widgets/lesson_ui_components.dart`
- Modify: `lib/features/learning/presentation/widgets/premium_exercise_widgets.dart`
- Modify: `lib/features/learning/presentation/widgets/quiz_widget.dart`
- Modify: `lib/features/learning/presentation/widgets/roadmap_header_widget.dart`
- Modify: `lib/features/learning/presentation/widgets/roadmap_node_widget.dart`
- Modify: `lib/features/practice/presentation/pages/practice_lab_page.dart`
- Modify: `lib/features/practice/presentation/widgets/practice_lab_navigation.dart`
- Modify: `lib/features/level/presentation/pages/placement_test_page.dart`
- Modify: `lib/features/level/presentation/widgets/level_widgets.dart`
- Modify: `lib/features/level/presentation/widgets/proficiency_card.dart`
- Test: `test/features/learning/learner_tactile_style_test.dart`

- [ ] **Step 1: Add failing representative tests**

Cover course card, roadmap node/card, answer option, practice card, proficiency
card, and placement option in both modes. Assert nested exercise rows have no
offset shadow. Observe category/course/lesson IDs on destination widgets and
verify the proficiency replacement operation preserves result and destination.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/features/learning/learner_tactile_style_test.dart`
Expected: FAIL on legacy decorations/routes.

- [ ] **Step 3: Migrate course screens**

Migrate the three course screens and their category/course/lesson pushes; run
course tests plus inventory and route guards.

- [ ] **Step 4: Migrate roadmap and session surfaces**

Migrate `learning_roadmap_screen.dart`, `learning_session_screen.dart`,
`roadmap_header_widget.dart`, and `roadmap_node_widget.dart`; run focused tests.

- [ ] **Step 5: Migrate lesson/exercise surfaces**

Migrate `lesson_content_widget.dart`, `lesson_ui_components.dart`,
`quiz_widget.dart`, and eligible occurrences in `premium_exercise_widgets.dart`;
keep inputs/media/decorative rows excluded and run focused learning tests.

- [ ] **Step 6: Migrate practice and level surfaces/routes**

Migrate the five practice/level files. Convert VoicePractice to
`LearnerRoute.push` and proficiency replacement to
`LearnerRoute.pushReplacement`; run practice/level and route tests.

- [ ] **Step 7: Close group 2–3 ledger rows**

Use semantic decorations and scoped button styles; leave excluded inputs,
charts, and plain lists unchanged. Mark the corresponding inventory rows done.

- [ ] **Step 8: Verify group**

Run: `flutter test test/features/course test/features/learning test/features/practice test/features/level test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart && flutter analyze`
Expected: PASS and no analyzer issues.

- [ ] **Step 9: Commit exact files**

```bash
git add docs/ui/learner-tactile-style-inventory.json lib/features/course/presentation/screens/course_list_screen.dart lib/features/course/presentation/screens/category_detail_screen.dart lib/features/course/presentation/screens/course_detail_screen.dart lib/features/learning/presentation/screens/learning_roadmap_screen.dart lib/features/learning/presentation/screens/learning_session_screen.dart lib/features/learning/presentation/widgets/lesson_content_widget.dart lib/features/learning/presentation/widgets/lesson_ui_components.dart lib/features/learning/presentation/widgets/premium_exercise_widgets.dart lib/features/learning/presentation/widgets/quiz_widget.dart lib/features/learning/presentation/widgets/roadmap_header_widget.dart lib/features/learning/presentation/widgets/roadmap_node_widget.dart lib/features/practice/presentation/pages/practice_lab_page.dart lib/features/practice/presentation/widgets/practice_lab_navigation.dart lib/features/level/presentation/pages/placement_test_page.dart lib/features/level/presentation/widgets/level_widgets.dart lib/features/level/presentation/widgets/proficiency_card.dart test/features/learning/learner_tactile_style_test.dart
git commit -m "feat: style learner course and practice flows"
```

### Task 7: Run the Chunk 2 gate

**Files:** None.

- [ ] **Step 1: Run group tests and guards**

Run: `flutter test test/core/widgets/app_button_tactile_style_test.dart test/features/home test/features/course test/features/learning test/features/practice test/features/level test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart`
Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`.

---

## Chunk 3: Content and Activity Flows

### Task 8: Migrate content discovery surfaces

**Files:**
- Modify: `docs/ui/learner-tactile-style-inventory.json`
- Modify: `lib/features/news/presentation/screens/news_list_screen.dart`
- Modify: `lib/features/news/presentation/screens/news_detail_screen.dart`
- Modify: `lib/features/news/presentation/screens/news_quiz_screen.dart`
- Modify: `lib/features/books/presentation/widgets/book_card.dart`
- Modify: `lib/features/books/presentation/widgets/reader_controls.dart`
- Modify: `lib/features/books/presentation/screens/book_library_screen.dart`
- Modify: `lib/features/books/presentation/screens/book_detail_screen.dart`
- Modify: `lib/features/books/presentation/screens/book_reader_screen.dart`
- Modify: `lib/features/books/presentation/screens/book_quiz_screen.dart`
- Modify: `lib/features/podcast/presentation/widgets/podcast_card.dart`
- Modify: `lib/features/podcast/presentation/widgets/episode_tile.dart`
- Modify: `lib/features/podcast/presentation/widgets/audio_player_controls.dart`
- Modify: `lib/features/podcast/presentation/widgets/transcript_panel.dart`
- Modify: `lib/features/podcast/presentation/screens/podcast_explore_screen.dart`
- Modify: `lib/features/podcast/presentation/screens/podcast_detail_screen.dart`
- Modify: `lib/features/podcast/presentation/screens/podcast_player_screen.dart`
- Modify: `lib/features/youtube/presentation/screens/youtube_explore_screen.dart`
- Modify: `lib/features/youtube/presentation/screens/youtube_player_screen.dart`
- Test: `test/features/content/content_tactile_style_test.dart`

- [ ] **Step 1: Add failing content-card tests**

Use the learner harness plus minimal provider/media fakes. Cover public list
cards, detail panels, quiz options, News word sheet, Book reader panels, Podcast
speed sheet, and YouTube dialogs/sheets in both modes; verify reader chrome and
media timelines remain excluded. Assert Book model/chapter and Podcast
episode/artwork arguments on pushed destination widgets.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/features/content/content_tactile_style_test.dart`
Expected: FAIL on legacy decorations.

- [ ] **Step 3: Migrate News**

Migrate the three News files, elevated dialog/sheet shells, and close their
group-4 ledger rows; run the content test and inventory guard.

- [ ] **Step 4: Migrate Books**

Migrate all six listed Book files. Convert Library→Detail and Detail→Reader/Quiz
imperative routes with `LearnerRoute.push`, preserve book/chapter arguments,
style eligible sheet shells, record reader-control exclusions, close Book rows,
and run tests/guards.

- [ ] **Step 5: Migrate Podcasts**

Migrate all seven listed Podcast files. Convert Explore→Detail and
Detail→Player pushes while preserving podcast/episode/artwork arguments; style
eligible speed/transcript panels, record timeline exclusions, and run guards.

- [ ] **Step 6: Migrate YouTube**

Migrate both YouTube screens and their dialog/sheet shells, keep named routes
named, close ledger rows, and run focused tests/guards.

- [ ] **Step 7: Verify content group**

Apply semantic variants according to the inventory, preserve media behavior,
and replace imperative page routes with `LearnerRoute.push`.

Run: `flutter test test/features/content/content_tactile_style_test.dart test/features/books test/features/news test/features/podcast test/features/youtube test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart && flutter analyze`
Expected: PASS and no analyzer issues.

- [ ] **Step 8: Commit exact files**

```bash
git add docs/ui/learner-tactile-style-inventory.json lib/features/news/presentation/screens/news_list_screen.dart lib/features/news/presentation/screens/news_detail_screen.dart lib/features/news/presentation/screens/news_quiz_screen.dart lib/features/books/presentation/widgets/book_card.dart lib/features/books/presentation/widgets/reader_controls.dart lib/features/books/presentation/screens/book_library_screen.dart lib/features/books/presentation/screens/book_detail_screen.dart lib/features/books/presentation/screens/book_reader_screen.dart lib/features/books/presentation/screens/book_quiz_screen.dart lib/features/podcast/presentation/widgets/podcast_card.dart lib/features/podcast/presentation/widgets/episode_tile.dart lib/features/podcast/presentation/widgets/audio_player_controls.dart lib/features/podcast/presentation/widgets/transcript_panel.dart lib/features/podcast/presentation/screens/podcast_explore_screen.dart lib/features/podcast/presentation/screens/podcast_detail_screen.dart lib/features/podcast/presentation/screens/podcast_player_screen.dart lib/features/youtube/presentation/screens/youtube_explore_screen.dart lib/features/youtube/presentation/screens/youtube_player_screen.dart test/features/content/content_tactile_style_test.dart
git commit -m "feat: style learner content discovery flows"
```

### Task 9: Migrate vocabulary, games, voice, and chat

**Files:**
- Modify: `docs/ui/learner-tactile-style-inventory.json`
- Modify: `lib/features/vocabulary/presentation/pages/vocab_library_page.dart`
- Modify: `lib/features/vocabulary/presentation/widgets/daily_review_card.dart`
- Modify: `lib/features/vocabulary/presentation/widgets/flashcard_widget.dart`
- Modify: `lib/features/vocabulary/presentation/widgets/quiz_option_card.dart`
- Modify: `lib/features/vocabulary/presentation/widgets/word_of_day_card.dart`
- Modify: `lib/features/vocabulary/presentation/widgets/vocab_word_detail_sheet.dart`
- Modify: `lib/features/vocabulary/presentation/screens/flashcard_review_screen.dart`
- Modify: `lib/features/vocabulary/presentation/screens/quiz_review_screen.dart`
- Modify: `lib/features/vocabulary/presentation/screens/session_complete_screen.dart`
- Modify: `lib/features/vocabulary/presentation/screens/vocabulary_speaking_practice_screen.dart`
- Modify: `lib/features/games/presentation/screens/games_hub_screen.dart`
- Modify: `lib/features/games/presentation/screens/game_result_screen.dart`
- Modify: `lib/features/games/presentation/screens/fill_blank_screen.dart`
- Modify: `lib/features/games/presentation/screens/grammar_quiz_screen.dart`
- Modify: `lib/features/games/presentation/screens/hangman_screen.dart`
- Modify: `lib/features/games/presentation/screens/matching_game_screen.dart`
- Modify: `lib/features/games/presentation/screens/spelling_bee_screen.dart`
- Modify: `lib/features/games/presentation/screens/word_scramble_screen.dart`
- Modify: `lib/features/games/presentation/widgets/level_up_dialog.dart`
- Modify: `lib/features/games/presentation/widgets/game_powerup_tray.dart`
- Modify: `lib/features/games/presentation/widgets/game_card.dart`
- Modify: `lib/features/games/presentation/widgets/daily_challenge_card.dart`
- Modify: `lib/features/games/presentation/widgets/letter_tile.dart`
- Modify: `lib/features/voice/presentation/screens/voice_practice_screen.dart`
- Modify: `lib/features/voice/presentation/widgets/pronunciation_score_card.dart`
- Modify: `lib/features/voice/presentation/widgets/playback_controls.dart`
- Modify: `lib/features/voice/presentation/widgets/record_button.dart`
- Modify: `lib/features/voice/presentation/widgets/speech_recognition_button.dart`
- Modify: `lib/features/voice/presentation/widgets/speak_button.dart`
- Modify: `lib/features/voice/presentation/widgets/tts_speed_selector.dart`
- Modify: `lib/features/chat/presentation/pages/story_selection_page.dart`
- Modify: `lib/features/chat/presentation/pages/topic_chat_page.dart`
- Modify: `lib/features/chat/presentation/widgets/topic_card.dart`
- Modify: `lib/features/chat/presentation/widgets/educational_hints_widgets.dart`
- Modify: `lib/features/chat/presentation/widgets/session_list_drawer.dart`
- Modify: `lib/features/lexi_chat/presentation/pages/lexi_chat_page.dart`
- Modify: `lib/features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart`
- Test: `test/features/activities/activity_tactile_style_test.dart`

- [ ] **Step 1: Add failing activity tests**

Use minimal vocabulary/game/recording/TTS/chat provider fakes. Cover flashcard,
quiz option, game card/tile, pronunciation card/control, topic card, and
correction sheet in both modes. Focus a custom card and use
`tester.sendKeyEvent(LogicalKeyboardKey.enter)` to verify activation. Assert
vocabulary/game/chat route destinations and replacement results.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/features/activities/activity_tactile_style_test.dart`
Expected: FAIL on legacy styles.

- [ ] **Step 3: Migrate vocabulary**

Migrate all listed vocabulary files, their dialogs/sheets, review/session route
pushes and replacements; preserve review models/results, close rows, run tests
and both guards.

- [ ] **Step 4: Migrate games**

Migrate all listed game screens/widgets, confirmation and level-up dialogs,
GamesHub pushes and result replacements; preserve game arguments/results, close
rows, and run tests/guards. Migrate `_PowerUpButton` enabled/loading states in
`game_powerup_tray.dart`; keep `ActivePowerUpBadge` excluded as a badge.

- [ ] **Step 5: Migrate voice**

Migrate the listed Voice screen/widgets, playback and speech-recognition action
controls, and TTS sheets while preserving recording/playback behavior;
explicitly exclude only timeline occurrences. Audit remaining group-5 rows such
as game power-up controls occurrence-by-occurrence, close rows, and run tests.

- [ ] **Step 6: Migrate Chat and Lexi**

Migrate listed Chat/Lexi pages/widgets, Story→Topic push, session dialogs and
correction sheets; preserve story/session arguments, exclude message bubbles,
close rows, and run tests/guards.

- [ ] **Step 7: Verify activity group**

Use semantic variants, preserve scoring/recording/chat state, exclude message
bubbles and audio timelines, and convert learner route pushes.

Run: `flutter test test/features/vocabulary test/features/games test/features/chat test/features/lexi_chat test/features/activities/activity_tactile_style_test.dart test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart && flutter analyze`
Expected: PASS and no analyzer issues.

- [ ] **Step 8: Commit exact files from the Files list**

```bash
git add docs/ui/learner-tactile-style-inventory.json lib/features/vocabulary/presentation/pages/vocab_library_page.dart lib/features/vocabulary/presentation/widgets/daily_review_card.dart lib/features/vocabulary/presentation/widgets/flashcard_widget.dart lib/features/vocabulary/presentation/widgets/quiz_option_card.dart lib/features/vocabulary/presentation/widgets/word_of_day_card.dart lib/features/vocabulary/presentation/widgets/vocab_word_detail_sheet.dart lib/features/vocabulary/presentation/screens/flashcard_review_screen.dart lib/features/vocabulary/presentation/screens/quiz_review_screen.dart lib/features/vocabulary/presentation/screens/session_complete_screen.dart lib/features/vocabulary/presentation/screens/vocabulary_speaking_practice_screen.dart lib/features/games/presentation/screens/games_hub_screen.dart lib/features/games/presentation/screens/game_result_screen.dart lib/features/games/presentation/screens/fill_blank_screen.dart lib/features/games/presentation/screens/grammar_quiz_screen.dart lib/features/games/presentation/screens/hangman_screen.dart lib/features/games/presentation/screens/matching_game_screen.dart lib/features/games/presentation/screens/spelling_bee_screen.dart lib/features/games/presentation/screens/word_scramble_screen.dart lib/features/games/presentation/widgets/game_card.dart lib/features/games/presentation/widgets/daily_challenge_card.dart lib/features/games/presentation/widgets/letter_tile.dart lib/features/games/presentation/widgets/level_up_dialog.dart lib/features/games/presentation/widgets/game_powerup_tray.dart lib/features/voice/presentation/screens/voice_practice_screen.dart lib/features/voice/presentation/widgets/pronunciation_score_card.dart lib/features/voice/presentation/widgets/playback_controls.dart lib/features/voice/presentation/widgets/record_button.dart lib/features/voice/presentation/widgets/speech_recognition_button.dart lib/features/voice/presentation/widgets/speak_button.dart lib/features/voice/presentation/widgets/tts_speed_selector.dart lib/features/chat/presentation/pages/story_selection_page.dart lib/features/chat/presentation/pages/topic_chat_page.dart lib/features/chat/presentation/widgets/topic_card.dart lib/features/chat/presentation/widgets/educational_hints_widgets.dart lib/features/chat/presentation/widgets/session_list_drawer.dart lib/features/lexi_chat/presentation/pages/lexi_chat_page.dart lib/features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart test/features/activities/activity_tactile_style_test.dart
git commit -m "feat: style learner activity surfaces"
```

### Task 10: Run the Chunk 3 gate

**Files:** None.

- [ ] **Step 1: Run group tests and guards**

Run: `flutter test test/features/content/content_tactile_style_test.dart test/features/activities/activity_tactile_style_test.dart test/features/books test/features/news test/features/podcast test/features/youtube test/features/vocabulary test/features/games test/features/chat test/features/lexi_chat test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart`
Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`.

---

## Chunk 4: User Utilities and Final Verification

### Task 11: Migrate profile, progress, and utility surfaces

**Files:**
- Modify: `docs/ui/learner-tactile-style-inventory.json`
- Modify: `lib/features/profile/presentation/pages/profile_page.dart`
- Modify: `lib/features/profile/presentation/pages/edit_profile_screen.dart`
- Modify: `lib/features/profile/presentation/pages/learning_stats_pages.dart`
- Modify: `lib/features/profile/presentation/widgets/profile_page/learning_stats_section.dart`
- Modify: `lib/features/profile/presentation/widgets/profile_page/level_progress_card.dart`
- Modify: `lib/features/profile/presentation/widgets/profile_page/profile_header.dart`
- Modify: `lib/features/profile/presentation/widgets/profile_page/quick_actions_row.dart`
- Modify: `lib/features/profile/presentation/widgets/profile_page/recent_badges_section.dart`
- Modify: `lib/features/profile/presentation/widgets/profile_page/weekly_activity_section.dart`
- Modify: `lib/features/profile/presentation/widgets/profile_ui_components.dart`
- Modify: `lib/features/progress/presentation/screens/my_progress_screen.dart`
- Modify: `lib/features/progress/presentation/widgets/progress_card.dart`
- Modify: `lib/features/progress/presentation/widgets/course_progress_card.dart`
- Modify: `lib/features/progress/presentation/widgets/daily_challenges_widget.dart`
- Modify: `lib/features/progress/presentation/widgets/daily_reward_dialog.dart`
- Modify: `lib/features/progress/presentation/widgets/points_calendar_dialog.dart`
- Modify: `lib/features/progress/presentation/widgets/streak_milestone_overlay.dart`
- Modify: `lib/features/progress/presentation/widgets/streak_widget.dart`
- Modify: `lib/features/achievements/presentation/screens/achievements_screen.dart`
- Modify: `lib/features/achievements/presentation/widgets/achievement_unlock_overlay.dart`
- Modify: `lib/features/achievements/presentation/widgets/achievement_widgets.dart`
- Modify: `lib/features/gamification/presentation/screens/leaderboard_screen.dart`
- Modify: `lib/features/gamification/presentation/screens/league_ceremony_screen.dart`
- Modify: `lib/features/gamification/presentation/screens/shop_screen.dart`
- Modify: `lib/features/gamification/presentation/screens/wallet_screen.dart`
- Modify: `lib/features/gamification/presentation/widgets/active_boosts_bar.dart`
- Modify: `lib/features/gamification/presentation/widgets/boost_purchase_animation.dart`
- Modify: `lib/features/gamification/presentation/widgets/league_card.dart`
- Modify: `lib/features/gamification/presentation/widgets/rank_up_dialog.dart`
- Modify: `lib/features/gamification/presentation/widgets/shop_item_card.dart`
- Modify: `lib/features/gamification/presentation/widgets/starter_reward_dialog.dart`
- Modify: `lib/features/social/presentation/screens/social_screen.dart`
- Modify: `lib/features/offline/presentation/pages/offline_sync_center_page.dart`
- Modify: `lib/features/premium/presentation/screens/paywall_screen.dart`
- Modify: `lib/features/notifications/presentation/pages/notifications_page.dart`
- Modify: `lib/features/notifications/presentation/widgets/empty_notification_widget.dart`
- Modify: `lib/features/user/presentation/pages/settings_page.dart`
- Modify: `lib/features/user/presentation/pages/legal_page.dart`
- Test: `test/features/profile/user_utility_tactile_style_test.dart`

- [ ] **Step 1: Add failing utility tests**

Use the learner harness with minimal fake profile/progress/gamification/social/
settings providers and fake purchase, sign-out, offline-clear, notification,
and profile-edit callbacks. Cover public profile summary/action, progress card,
achievement/shop item, social card, settings group, and overlays in both modes;
drive pressed/focus states. Assert `AdminPanelTile` inline decoration is
value-equivalent in both modes and tapping it pushes raw fullscreen `AdminApp`
with no `AppTactileTheme` extension.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/features/profile/user_utility_tactile_style_test.dart`
Expected: FAIL on legacy eligible surfaces.

- [ ] **Step 3: Migrate Profile and learner routes**

Migrate the ten listed Profile files. Convert Shop, Leaderboard, Social,
Progress, Wallet, Settings, and learner stats pushes to `LearnerRoute.push`,
preserving arguments/results. Keep the Profile→AdminApp fullscreen
`MaterialPageRoute` raw and unwrapped. Close Profile rows and run profile tests
plus both guards.

- [ ] **Step 4: Migrate Progress and overlays**

Migrate the eight listed Progress files, including daily reward, calendar, and
streak overlay shells; preserve chart/badge exclusions and provider behavior.
Close rows and run progress tests plus guards.

- [ ] **Step 5: Migrate Achievements and Gamification**

Migrate the three Achievement and ten Gamification files, Shop→Wallet learner
route, eligible cards/buttons/dialog shells, and preserve purchase/reward logic.
Close rows and run gamification/new utility tests with fakes plus guards.

- [ ] **Step 6: Migrate Social**

Migrate `social_screen.dart` cards and sheet shell, preserve network/provider
logic, close rows, and run the utility test plus inventory guard.

- [ ] **Step 7: Migrate Offline, Premium, and Notifications**

Migrate the four listed files, eligible cards/controls/dialogs only, preserve
sync/purchase/notification behavior through fakes, close rows, and run existing
offline/notification plus utility tests and guards.

- [ ] **Step 8: Migrate Settings and Legal**

Migrate `settings_page.dart` and `legal_page.dart`, convert learner Legal pushes
to `LearnerRoute.push`, preserve sign-out/delete/settings behavior through fakes,
close rows, and run user tests plus route/inventory guards.

- [ ] **Step 9: Verify utility group**

Apply semantic styles and learner route helper without changing auth, purchase,
sync, notification, or settings behavior. Update every completed ledger row.

- [ ] **Step 10: Run the Chunk 4 utility gate**

Run: `flutter test test/features/profile test/features/progress test/features/gamification test/features/offline test/features/notifications test/features/user test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart test/core/theme/app_tactile_theme_test.dart && flutter analyze`
Expected: PASS and no analyzer issues.

- [ ] **Step 11: Commit exact files from this task's Files list**

```bash
git add docs/ui/learner-tactile-style-inventory.json lib/features/profile/presentation/pages/profile_page.dart lib/features/profile/presentation/pages/edit_profile_screen.dart lib/features/profile/presentation/pages/learning_stats_pages.dart lib/features/profile/presentation/widgets/profile_page/learning_stats_section.dart lib/features/profile/presentation/widgets/profile_page/level_progress_card.dart lib/features/profile/presentation/widgets/profile_page/profile_header.dart lib/features/profile/presentation/widgets/profile_page/quick_actions_row.dart lib/features/profile/presentation/widgets/profile_page/recent_badges_section.dart lib/features/profile/presentation/widgets/profile_page/weekly_activity_section.dart lib/features/profile/presentation/widgets/profile_ui_components.dart lib/features/progress/presentation/screens/my_progress_screen.dart lib/features/progress/presentation/widgets/progress_card.dart lib/features/progress/presentation/widgets/course_progress_card.dart lib/features/progress/presentation/widgets/daily_challenges_widget.dart lib/features/progress/presentation/widgets/daily_reward_dialog.dart lib/features/progress/presentation/widgets/points_calendar_dialog.dart lib/features/progress/presentation/widgets/streak_milestone_overlay.dart lib/features/progress/presentation/widgets/streak_widget.dart lib/features/achievements/presentation/screens/achievements_screen.dart lib/features/achievements/presentation/widgets/achievement_unlock_overlay.dart lib/features/achievements/presentation/widgets/achievement_widgets.dart lib/features/gamification/presentation/screens/leaderboard_screen.dart lib/features/gamification/presentation/screens/league_ceremony_screen.dart lib/features/gamification/presentation/screens/shop_screen.dart lib/features/gamification/presentation/screens/wallet_screen.dart lib/features/gamification/presentation/widgets/active_boosts_bar.dart lib/features/gamification/presentation/widgets/boost_purchase_animation.dart lib/features/gamification/presentation/widgets/league_card.dart lib/features/gamification/presentation/widgets/rank_up_dialog.dart lib/features/gamification/presentation/widgets/shop_item_card.dart lib/features/gamification/presentation/widgets/starter_reward_dialog.dart lib/features/social/presentation/screens/social_screen.dart lib/features/offline/presentation/pages/offline_sync_center_page.dart lib/features/premium/presentation/screens/paywall_screen.dart lib/features/notifications/presentation/pages/notifications_page.dart lib/features/notifications/presentation/widgets/empty_notification_widget.dart lib/features/user/presentation/pages/settings_page.dart lib/features/user/presentation/pages/legal_page.dart test/features/profile/user_utility_tactile_style_test.dart
git commit -m "feat: style learner profile and utility surfaces"
```

### Task 12: Audit coverage and run the full gate

**Files:**
- Modify: `docs/ui/learner-tactile-style-inventory.json`
- Modify only when a reproduced audit miss requires it: the exact test files
  created in Tasks 1–11. Record any additional file in the plan execution log
  before editing it.

- [ ] **Step 1: Run inventory and scoped regression tests**

Run: `flutter test test/core/navigation/learner_surface_inventory_test.dart test/core/navigation/learner_route_test.dart test/core/theme/app_tactile_theme_test.dart`
Expected: PASS; every included row is completed or has a documented exception.

- [ ] **Step 2: Run formatting and inspect the diff**

Run: `dart format --output=none --set-exit-if-changed lib test`
Expected: exit 0. Inspect `git diff --check` and verify no Admin/auth presentation
file is changed except route-scope regression fixtures if required.

- [ ] **Step 3: Run full tests**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 5: Dispatch required reviews**

Dispatch the AGENTS.md test-writer to audit missing behavioral/widget coverage.
Implement findings, list each intentionally changed file, and rerun focused
tests. Then dispatch code-reviewer to inspect correctness, contrast, route
scoping, Admin exclusion, and unnecessary abstractions. Implement findings and
rerun the inventory guard, route/theme tests, full `flutter test`, and
`flutter analyze` before committing.

- [ ] **Step 6: Final commit**

```bash
git diff --name-only
# Review the output, then git add only the intentional audit/review-fix paths.
git commit -m "test: verify learner tactile style rollout"
```
