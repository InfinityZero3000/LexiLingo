# Cross-Platform Theme Reliability Design

## Goal

Restore immediate theme switching from Settings on Flutter Web and make the
same behavior reliable on Android and iOS. Audit recently added or modified
learner-facing screens for light/dark contrast regressions and reduce the
theme-related technical debt encountered in that scope.

## Current Problem

`MaterialApp` already consumes `SettingsProvider.themeMode`, but the selected
theme currently depends on user settings being loaded and persisted through
the settings repository. This couples a device-level presentation preference
to authentication, database rows, and reminder-preference synchronization.

The current persistence path also has two reliability gaps:

- A theme choice has no independent app-level cache from which the provider
  can bootstrap before user settings load.
- The native SQLite implementation can update zero rows without treating that
  result as a persistence failure or creating the missing row.

The UI therefore has no single, immediate, platform-independent source of
truth for the selected theme.

## Architecture

### Theme Preference Store

Add a small local store backed by the existing `SharedPreferences` singleton.
It owns one validated value: `light`, `dark`, or `system`.

Its interface provides:

- A synchronous cached read for app bootstrap.
- An asynchronous write for persistence.
- Normalization of missing or malformed values to `system`.

The preference is device-local and app-global. It is available before
authentication and behaves consistently across web, Android, and iOS.

### Settings Provider

`SettingsProvider` remains the public presentation API and the object consumed
by `MaterialApp`. It receives the theme preference store through dependency
injection and initializes its effective theme from the store immediately.

The provider keeps theme state separate from the nullable user settings
record:

- `theme` and `themeMode` read the effective local theme.
- `updateTheme` validates the requested value, updates memory, and notifies
  listeners synchronously.
- The local preference is persisted after notification.
- If user settings are loaded, their theme field is updated and repository
  persistence runs as secondary synchronization.
- Repository or network failure must not roll back the visible theme.

When settings load:

1. If a local theme preference exists, it remains authoritative and is copied
   into the in-memory user settings.
2. If no local preference exists, a valid legacy theme from user settings is
   adopted and written to the new store.
3. If neither source has a valid value, `system` is used.

This preserves existing users' choices during migration while preventing a
later settings reload from overwriting a newly selected device theme.

### Repository Persistence

Keep the existing local-first repository behavior. Harden the native settings
data source so an update that affects zero rows creates the settings record.
Web persistence continues to use `SharedPreferences`.

Remote reminder-preference synchronization remains unchanged. Theme switching
does not wait for it and does not send theme data to an endpoint that only
owns reminder fields.

## Settings UI Behavior

The three controls continue to select `light`, `dark`, and `system`.

On selection:

- The selected indicator updates immediately.
- `MaterialApp` rebuilds in the selected mode in the same interaction.
- `system` resolves from platform brightness and responds to later platform
  brightness changes through Flutter's normal `ThemeMode.system` behavior.
- The entire option area remains keyboard- and pointer-activatable on web.
- A persistence error may be recorded for diagnostics, but it must not make
  the control appear unresponsive or revert the active theme.

No visual redesign of the Settings selector is required.

## Light/Dark Color Audit

Audit recently added or currently modified learner-facing surfaces, with
priority on:

- Premium learning exercise widgets.
- Learning session chrome and answer feedback.
- Course list, category detail, and course detail screens.
- Topic chat and Lexi Chat widgets.
- YouTube explore changes.

Replace hard-coded colors when they represent a semantic surface, border,
primary text, secondary text, muted text, or disabled state. Use
`ThemeData.colorScheme`, `ThemeData.textTheme`, and existing `AppColorRoles`
or `AppColors` tokens.

Intentional content colors may remain fixed when contrast is preserved in both
modes, including success/error feedback, badges, image overlays, avatars, and
white foreground text on known dark or saturated backgrounds.

The premium exercise file's light-only card, surface, border, and text
constants will be converted to context-derived semantic colors. Shared color
resolution should be centralized within that file or the existing theme
module rather than repeated per widget.

## Technical Debt Boundaries

Address theme debt that directly affects this workflow:

- Duplicate theme state derived from nullable settings.
- Persistence coupled to unrelated remote reminder synchronization.
- Native zero-row settings updates.
- Light-only semantic colors in the audited screens.
- Missing tests for theme selection, migration, and persistence.

Do not perform a repository-wide color-token rewrite, redesign unrelated
screens, change backend APIs, or merge the separate `UserProvider` settings
API as part of this fix. Remaining out-of-scope color debt should be reported
with file references after the focused audit.

## Error Handling

- Unknown persisted or requested theme values normalize to `system`.
- Local persistence failures keep the in-memory selection active and expose a
  provider error for diagnostics.
- User-settings persistence failures do not roll back the local theme.
- Missing native settings rows are created during update.
- Loading user settings cannot overwrite an existing local preference.

## Verification

Add focused tests for:

- Mapping `light`, `dark`, and `system` to the correct `ThemeMode`.
- Immediate listener notification before asynchronous persistence completes.
- Theme persistence and restoration with `SharedPreferences`.
- Legacy user-setting migration when no local preference exists.
- Local preference precedence when user settings load later.
- Invalid-value normalization.
- No rollback when repository synchronization fails.
- Native settings update fallback when no row exists.
- Settings selector interaction and selected-state update.
- Representative premium exercise rendering in both light and dark themes.

Run Dart formatting, focused Flutter tests, the broader relevant test suite,
and `flutter analyze`. Where practical, manually verify Flutter Web in both
light and dark modes and check `system` against browser/OS brightness.
