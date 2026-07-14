import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/quick_actions_grid.dart';

void main() {
  testWidgets('home quick actions no longer include Practice Lab', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QuickActionsGrid())),
    );

    expect(find.byIcon(Icons.science_rounded), findsNothing);
    expect(find.byType(GestureDetector), findsNWidgets(6));
  });

  test('profile app bar opens Practice Lab instead of Voice', () {
    final source = File(
      'lib/features/profile/presentation/pages/profile_page.dart',
    ).readAsStringSync();

    expect(source, contains('Icons.science_rounded'));
    expect(source, contains("'practiceLab.shortTitle'.tr()"));
    expect(source, contains("Navigator.pushNamed(context, '/practice-lab')"));
    expect(source, isNot(contains('VoicePracticeScreen')));
  });
}
