# Move Practice Lab Entry

## Goal

Move the existing Practice Lab navigation entry from the Home quick-actions grid to the Profile app bar, replacing the existing Voice Practice button.

## Design

- Remove only the Practice Lab item from `QuickActionsGrid`; retain all other quick actions and their existing order.
- Replace the Profile app bar's Voice Practice `IconButton` with a Practice Lab button.
- Reuse the existing `Icons.science_rounded` icon and `/practice-lab` named route.
- Give the replacement button a clear `Practice Lab` tooltip.
- Leave the Voice Practice screen, providers, and routes intact because they may still be used elsewhere.

## Data Flow and Error Handling

The Profile button calls `Navigator.pushNamed(context, '/practice-lab')`. The route is already registered by the application. No new state, network calls, or error handling are required.

## Verification

- A widget test confirms the Home quick-actions grid no longer displays or navigates through the Practice Lab item.
- A widget test or existing navigation coverage confirms the Profile app bar exposes Practice Lab instead of Voice Practice.
- Run `flutter analyze` and the focused Flutter tests.

## Scope

No redesign, route removal, localization expansion, or Voice Practice deletion is included.
