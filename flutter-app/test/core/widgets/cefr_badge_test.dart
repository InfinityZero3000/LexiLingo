import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(body: Center(child: child)),
  );

  group('CefrBadge', () {
    test('isMilestone returns true for A1/A2', () {
      for (final level in ['A1', 'A2']) {
        final color = CefrBadge.colorForLevel(level);
        expect(color, AppColors.cefrA, reason: '$level should be cefrA');
      }
    });

    test('colorForLevel returns cefrB for B1/B2', () {
      for (final level in ['B1', 'B2']) {
        final color = CefrBadge.colorForLevel(level);
        expect(color, AppColors.cefrB, reason: '$level should be cefrB');
      }
    });

    test('colorForLevel returns cefrC for C1/C2', () {
      for (final level in ['C1', 'C2']) {
        final color = CefrBadge.colorForLevel(level);
        expect(color, AppColors.cefrC, reason: '$level should be cefrC');
      }
    });

    test('colorForLevel returns grey for unknown level', () {
      final color = CefrBadge.colorForLevel('X9');
      expect(color, AppColors.grey500);
    });

    testWidgets('renders level text', (tester) async {
      await tester.pumpWidget(wrap(const CefrBadge(level: 'B2')));
      expect(find.text('B2'), findsOneWidget);
    });

    testWidgets('small size renders without overflow', (tester) async {
      await tester.pumpWidget(
        wrap(const CefrBadge(level: 'A1', size: CefrBadgeSize.small)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('large size renders without overflow', (tester) async {
      await tester.pumpWidget(
        wrap(const CefrBadge(level: 'C2', size: CefrBadgeSize.large)),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
