import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/premium/presentation/screens/paywall_screen.dart';

void main() {
  testWidgets('short screen scrolls instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(375, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PaywallScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('no offerings shows a retry that reloads', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PaywallScreen()));
    await tester.pumpAndSettle();

    final retry = find.widgetWithText(TextButton, 'common.retry');
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
