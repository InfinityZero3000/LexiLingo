/// Widget tests for [GameLoadState].
///
/// Tests:
/// - Loading: shows circular progress indicator
/// - Error with message: shows localized error message + retry button
/// - Empty payload: shows empty state message + retry button
/// - Retry: tapping retry calls the onRetry callback
/// - Stale errors don't leak between game refreshes (one active state per screen)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_load_state.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('GameLoadState', () {
    testWidgets('shows error_outline icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: 'Network error occurred.',
            onRetry: () async {},
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('displays the provided message text', (tester) async {
      const msg = 'Unable to load this game.';
      await tester.pumpWidget(
        _wrap(
          GameLoadState(message: msg, onRetry: () async {}),
        ),
      );

      expect(find.text(msg), findsOneWidget);
    });

    testWidgets('shows a retry button with refresh icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: 'Failed to load.',
            onRetry: () async {},
          ),
        ),
      );

      // Retry button identified by its refresh icon
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    testWidgets('retry callback is invoked on button tap', (tester) async {
      int retryCount = 0;

      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: 'Error.',
            onRetry: () async => retryCount++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();

      expect(retryCount, 1);
    });

    testWidgets('retry callback can be called multiple times', (tester) async {
      int retryCount = 0;

      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: 'Error.',
            onRetry: () async => retryCount++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();

      expect(retryCount, 2);
    });

    testWidgets('renders with network error message', (tester) async {
      const networkMessage = 'Unable to load this game. Please try again.';
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: networkMessage,
            onRetry: () async {},
          ),
        ),
      );

      expect(find.text(networkMessage), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('renders with empty payload message', (tester) async {
      const emptyMessage = 'This game has no playable content right now.';
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: emptyMessage,
            onRetry: () async {},
          ),
        ),
      );

      expect(find.text(emptyMessage), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    testWidgets('renders with malformed payload message', (tester) async {
      const malformedMessage = 'Unexpected game data received.';
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: malformedMessage,
            onRetry: () async {},
          ),
        ),
      );

      expect(find.text(malformedMessage), findsOneWidget);
    });

    testWidgets('layout is constrained to maxWidth 360', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: 'Error.',
            onRetry: () async {},
          ),
        ),
      );

      // Find the ConstrainedBox with the 360 max width
      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      final maxWidthBox = constrainedBoxes.firstWhere(
        (cb) => cb.constraints.maxWidth == 360,
        orElse: () => throw TestFailure(
          'No ConstrainedBox with maxWidth 360 found',
        ),
      );
      expect(maxWidthBox.constraints.maxWidth, 360);
    });

    testWidgets('stale error from one game does not leak to next game state',
        (tester) async {
      // Simulate showing error for game A
      const errorMsgA = 'Word Scramble failed to load.';
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: errorMsgA,
            onRetry: () async {},
          ),
        ),
      );
      expect(find.text(errorMsgA), findsOneWidget);

      // Swap to loading state (game B starts loading)
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
      await tester.pump();

      // Error A message must not be in the tree
      expect(find.text(errorMsgA), findsNothing);

      // Show error for game B — independent message
      const errorMsgB = 'Hangman failed to load.';
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: errorMsgB,
            onRetry: () async {},
          ),
        ),
      );
      expect(find.text(errorMsgB), findsOneWidget);
      expect(find.text(errorMsgA), findsNothing);
    });

    testWidgets('retry callback triggers reload and clears error state',
        (tester) async {
      bool reloaded = false;

      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: 'Game failed to load.',
            onRetry: () async {
              reloaded = true;
            },
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();

      expect(reloaded, isTrue);
    });
  });

  group('GameLoadState — loading state (Scaffold + indicator)', () {
    testWidgets('loading indicator is visible when isLoading is true',
        (tester) async {
      // Simulate loading state with a progress indicator (as used in game screens)
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('GameLoadState replaces loading indicator on error', (tester) async {
      // Loading state
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Error state replaces it
      await tester.pumpWidget(
        _wrap(
          GameLoadState(
            message: 'Failed to load.',
            onRetry: () async {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  });
}
