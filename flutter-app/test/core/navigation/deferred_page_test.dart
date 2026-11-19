import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/navigation/deferred_page.dart';
import 'package:lexilingo_app/core/navigation/deferred_prefetch.dart';

void main() {
  Widget host(DeferredLibraryLoader load) => MaterialApp(
    home: DeferredPage(
      loadLibrary: load,
      builder: (_) => const Scaffold(body: Text('loaded page')),
    ),
  );

  testWidgets('shows a loading state, then the page', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(host(() => gate.future));

    expect(find.text('loaded page'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('loaded page'), findsOneWidget);
  });

  testWidgets('shows retry when the chunk fails, and loads on retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(() async {
        calls++;
        if (calls == 1) throw Exception('chunk fetch failed');
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('loaded page'), findsNothing);
    expect(find.text('common.tryAgain'), findsOneWidget);

    await tester.tap(find.text('common.tryAgain'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('loaded page'), findsOneWidget);
  });

  testWidgets('offers a full reload after a second failure on the web', (
    tester,
  ) async {
    var calls = 0;
    var reloads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredPage(
          loadLibrary: () async {
            calls++;
            throw Exception('hash mismatch');
          },
          builder: (_) => const Text('loaded page'),
          offerReload: true,
          onReload: () => reloads++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('common.tryAgain'), findsOneWidget);
    expect(find.text('home.reload'), findsNothing);

    await tester.tap(find.text('common.tryAgain'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('common.tryAgain'), findsNothing);
    expect(find.text('home.reload'), findsOneWidget);

    await tester.tap(find.text('home.reload'));
    expect(reloads, 1);
    expect(calls, 2);
  });

  test(
    'prefetch loads every chunk, ignores failures, and skips signed out',
    () async {
      final loaded = <String>[];
      prefetchDeferredFeatures(
        isSignedIn: () => false,
        delay: Duration.zero,
        loaders: [() async => loaded.add('x')],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loaded, isEmpty);

      prefetchDeferredFeatures(
        isSignedIn: () => true,
        delay: Duration.zero,
        loaders: [
          () async => throw Exception('offline'),
          () async => loaded.add('b'),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loaded, ['b']);
    },
  );
}
