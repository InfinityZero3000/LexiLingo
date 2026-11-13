import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/quick_actions_grid.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: QuickActionsGrid()),
        ),
      ),
    );
  }

  double rowOf(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  testWidgets('phone width: two full rows of three', (tester) async {
    await pumpAt(tester, 375);

    expect(rowOf(tester, 'home.youtube'), rowOf(tester, 'home.games'));
    expect(rowOf(tester, 'home.podcast'), rowOf(tester, 'home.vocabulary'));
    expect(
      rowOf(tester, 'home.youtube'),
      lessThan(rowOf(tester, 'home.podcast')),
    );
  });

  for (final width in [600.0, 768.0, 1280.0]) {
    testWidgets('$width wide: one row, never a short last row', (tester) async {
      await pumpAt(tester, width);

      expect(rowOf(tester, 'home.youtube'), rowOf(tester, 'home.vocabulary'));
    });
  }

  testWidgets('200% text on a phone: tiles grow, nothing overflows', (
    tester,
  ) async {
    await pumpAt(tester, 375, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('home.vocabulary'), findsOneWidget);
  });
}
