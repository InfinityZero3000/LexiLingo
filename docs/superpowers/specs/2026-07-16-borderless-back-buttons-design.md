# Borderless Back Buttons

## Goal

Remove the black circular border from every navigation Back button in the Flutter application.

## Design

- Add one shared `AppBackButton` based on Flutter's native `IconButton`.
- Accept the existing back icon as an optional parameter and override only the button border with `BorderSide.none`.
- Preserve a transparent background, localized Back tooltip, minimum 48x48 touch target, ripple, and callback behavior. When no callback is supplied, use `Navigator.maybePop`.
- Replace only buttons whose callback pops, maybe-pops, or dismisses the current route/dialog. Inventory these by searching `BackButton` and back-arrow `IconButton` usages before migration.
- Do not change month navigation, media controls, bookmarks, menus, or other circular icon buttons.

## Verification

- Widget tests verify no border, callback invocation, default `Navigator.maybePop`, tooltip, and minimum touch target.
- Re-run the inventory search to ensure no route Back button still inherits the circular border; previous-month/media controls are explicitly excluded.
- Run the focused widget test and `flutter analyze` on changed files.
