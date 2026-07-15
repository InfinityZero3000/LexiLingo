# User Surface Style System Design

## Goal

Apply the Home screen's tactile visual language—colored borders, offset shadows,
and clearly outlined controls—to every learner-facing screen in both light and
dark mode, without changing Admin UI or flattening feature-specific colors.

## Scope

Included:

- Authenticated learner screens reachable from `MainScreen`, named learner
  routes registered in `lib/main.dart`, and direct `Navigator` pushes from
  those screens.
- Learner dialogs, sheets, cards, tiles, buttons, and icon controls.
- Light and dark themes, including pressed, focused, disabled, and loading
  states.

Excluded:

- `lib/features/admin/**`.
- `admin_panel_tile.dart` and Admin-only navigation.
- Authentication, registration, password reset, email verification, welcome,
  onboarding, and pre-auth questionnaire screens.
- Layout, typography, data flow, navigation, and business-logic redesigns.
- New dependencies or a wholesale replacement of existing widgets.

## Current State

The app does not have one card abstraction. Material `Card` widgets coexist
with custom `Container + BoxDecoration` implementations. The repository has
roughly 250 `Card` usages, 176 files with custom `BoxDecoration`, and 91 files
with `BoxShadow`; `AppButton` currently has only one caller. Therefore changing
`ThemeData` alone cannot produce consistent coverage, while forcing all UI
through new wrapper widgets would create a risky, unnecessary rewrite.

## Chosen Architecture

Use complementary scoped layers:

1. Add `AppTactileTheme`, an immutable `ThemeExtension` in
   `lib/core/theme/app_tactile_theme.dart`. It exposes three semantic surface
   variants (`elevated`, `interactive`, and `nested`) and resolves a
   `BoxDecoration` from the required fill, optional accent, radius, brightness,
   and `WidgetState` set. It also exposes concrete `ButtonStyle` builders for
   filled, outlined, text, and icon controls. Those builders own
   `WidgetStateProperty` values for border, foreground, background, overlay,
   and disabled/focused/pressed states.
2. Add a small `LearnerTheme` wrapper in the same file. It scopes Material
   `Card`, `ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton`, and
   `IconButton` defaults to authenticated learner route contents only.
   `MaterialApp.theme` and `MaterialApp.darkTheme` remain unchanged for Admin
   and pre-auth surfaces.
3. Custom `Container + BoxDecoration` implementations call the extension
   resolver. They are not replaced by a new card widget.
4. Add one shared learner route API in
   `lib/core/navigation/learner_route.dart`: `LearnerRoute.builder` wraps named
   route contents, and `LearnerRoute.push` creates wrapped imperative
   `MaterialPageRoute`s. `MainScreen`, every named learner route, and every
   learner `MaterialPageRoute` destination in the coverage inventory must use
   this API. This avoids assuming that a route pushed onto the root Navigator
   inherits a page-local `Theme`.

The semantic API owns contrast and mode-specific values. Feature widgets keep
their existing accent, fill, radius, and layout unless accessibility requires a
small adjustment. No generic `AppCard` wrapper is introduced unless inventory
finds repeated behavior that decoration values cannot express.

`WidgetState.disabled`, `pressed`, and `focused` are resolved centrally for
Material controls. Custom actionable cards use `InkWell`/`InkResponse` as the
native interaction source: `onHighlightChanged` supplies pressed state,
`onFocusChange` supplies focused state, and the widget's built-in ActivateIntent
handling keeps Enter/Space activation and semantics aligned with `onTap`.
Existing `GestureDetector` card taps are migrated only where this interaction
state is required. Static cards and nested rows do not gain state machinery.

## Coverage Inventory

Before migration, create a checked-in inventory mapping every authenticated
learner entry point to its presentation files. The inventory must include named
routes, `MainScreen` tabs, `MaterialPageRoute`/`Navigator.push` destinations,
dialogs, and bottom sheets. Each row records one of: `elevated`, `interactive`,
`nested`, `control`, or `excluded`, plus its rollout group and any exception
reason.

The boundary is:

| Entry family | Included | Notes |
|---|---:|---|
| `MainScreen` Home, Learning, Lexi, Topic, Account tabs | Yes | Includes direct descendants and pushes |
| Course, practice, placement, vocabulary, progress | Yes | Authenticated learner flows |
| News, books, podcasts, YouTube, games, voice | Yes | Content and activity flows |
| Achievements, gamification, social, premium, offline, notifications, settings/legal | Yes | User utilities and overlays |
| `features/admin/**`, Admin navigation/tile | No | Must remain visually unchanged |
| Auth, register, reset password, verification, welcome/onboarding/pre-auth | No | Outside authenticated learner scope |

The inventory is the completion ledger; a route family cannot be declared done
until every row is migrated or has an explicit exclusion reason.

## Visual Rules

### Cards and tiles

- Surface cards retain their current fill.
- Interactive and featured cards receive a visible semantic border and a short
  downward offset shadow, matching the Home streak and quick-action treatment.
- Neutral informational cards use a neutral outline/shadow; colored cards derive
  both from their accent.
- Nested rows inside a parent card use borders without full elevation to avoid
  visual noise.

Eligible surfaces are bounded as follows:

- `elevated`: standalone cards, featured banners, summary panels, and dialogs.
- `interactive`: tappable cards, quick actions, selectable answers, and list
  tiles that visually act as cards.
- `nested`: rows or grouped sections already enclosed by an elevated surface;
  border only, no offset shadow.
- `control`: buttons and icon controls described below.
- Excluded: plain edge-to-edge lists, separators, chips/badges, text fields,
  navigation bars/items, media timelines, message bubbles, decorative
  backgrounds, skeletons, charts, and invisible layout containers unless a
  feature-specific reason is recorded in the inventory.

### Buttons and icon controls

- Filled controls use a darker/lighter tonal edge.
- Outlined controls use a stronger border than the current default.
- Ghost/text controls do not gain a card-like shadow; their focus/pressed state
  remains visible.
- Disabled controls keep sufficient text/icon contrast and suppress misleading
  elevation.
- Standard Material buttons receive the strong border and clear state styling
  requested by the reference, but retain native Material elevation behavior;
  no custom wrapper is added solely to create an offset button shadow. Custom
  icon/action controls that already use `BoxDecoration` use the pressed offset.

Canonical values are deliberately small and shared:

- Card/control border: `2.0` logical pixels; nested border: `1.5`.
- Resting custom-surface shadow: `Offset(0, 4)`, zero blur and spread.
- Pressed custom-surface shadow: `Offset(0, 1)`, zero blur and spread.
- Disabled controls: no shadow; focus indicator remains `2.0`.
- Existing radius is preserved; new surfaces default to `16.0`.
- Light shadow uses accent at `0.18` alpha, or neutral black at `0.10` when no
  accent exists. Dark shadow uses black at `0.35`.

Border colors use a deterministic resolver. It converts the opaque accent to
HSL and evaluates this fixed candidate list in order: accent; the same hue and
saturation with lightness `L-0.15`, `L+0.15`, `L-0.30`, and `L+0.30` (each
clamped to `0..1`); `colorScheme.onSurface`; black; white. For each candidate it
computes the minimum contrast against the fill and page background, selects the
highest value, and resolves ties by the listed order. If the winner is below
`3:1`, the inventory must provide a neutral intermediate fill and rerun the
resolver before migration; silently accepting a failing border is not allowed.
Individual feature files do not invent alpha values.

When `accent == null`, the resolver skips the HSL candidates and evaluates the
fixed neutral list `colorScheme.onSurface`, black, then white with the same
contrast calculation and tie ordering.

### Light and dark mode

- Light mode uses darker accent-derived borders and low-alpha accent shadows.
- Dark mode uses lighter accent-derived borders and darker neutral shadows so
  edges remain visible without neon bloom.
- Contrast is verified for text, icons, borders, and disabled states; colors are
  never copied blindly from light to dark mode.
- Normal text must meet WCAG AA `4.5:1`; large text and essential icons `3:1`;
  component boundaries and focus indicators `3:1` against adjacent colors.
  Disabled controls are exempt from the WCAG contrast minimum but must remain
  visibly distinguishable and are covered by widget regression tests.

## Rollout

Migration is split into independently testable groups:

1. Core theme and semantic style tests.
2. Coverage inventory, scoped learner theme, app shell, and Home.
3. Course, learning, practice, and placement flows.
4. News, books, podcasts, and YouTube.
5. Vocabulary, games, voice, and Lexi/chat.
6. Profile, progress, achievements, gamification, social, offline, premium,
   notifications, settings, and legal screens.
7. Learner dialogs and bottom sheets, followed by a route inventory audit.

Each group reuses the semantic API and changes only presentation code. Files are
not migrated through blind search-and-replace.

## Testing and Verification

- Unit/widget tests validate semantic values in light and dark mode.
- Numeric tests use `Color.computeLuminance()` to assert the WCAG contrast
  ratios for canonical foreground/background, border/fill, border/page, and
  focus/background pairs in both modes.
- Resolver parameter tests cover every unique accent/fill/page combination
  collected by the coverage inventory, rather than testing only default theme
  colors.
- Representative widget tests cover standard Material components and custom
  decorated cards, including enabled, pressed, and disabled controls.
- Golden tests are limited to representative Home, content-list, exercise, and
  profile surfaces in both modes; they are not duplicated per route.
- A regression test builds one Admin screen and one pre-auth screen outside
  `LearnerTheme` and proves their inherited component themes are unchanged.
- Route tests prove named and imperative learner destinations are wrapped in
  `LearnerTheme`, while Admin and pre-auth destinations are not.
- Existing feature tests run after each migration group.
- The final gate is `flutter test` followed by `flutter analyze`.
- The test-writer agent reviews test coverage after implementation; the
  code-reviewer agent performs the final non-trivial change review.

## Risk Controls

- Preserve existing navigation, provider, and async behavior.
- Exclude Admin paths explicitly in both inventory and review.
- Scope theme changes through `LearnerTheme`; never change global component
  themes in `AppTheme.lightTheme` or `AppTheme.darkTheme`.
- Avoid one giant migration commit; each group must remain buildable and
  testable.
- Do not add a wrapper or token unless at least two real consumers need it.
- Record any intentionally deferred visual exception with its file and reason,
  rather than silently leaving inconsistent UI.

## Success Criteria

- Every included inventory row is migrated or has an approved exception, and
  eligible learner cards/controls use the canonical tactile values in light and
  dark mode.
- Admin UI is unchanged.
- Feature accents remain recognizable and contrast is adequate.
- No new dependency, business-logic change, analyzer issue, or test regression.
- Shared style definitions replace duplicated border/shadow literals where the
  same behavior is required.
