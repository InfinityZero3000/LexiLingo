import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/navigation/deferred_page.dart';

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
}
