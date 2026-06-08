import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/starter_reward_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows gem amount and requires the action button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StarterRewardDialog(gems: 100))),
    );
    await tester.pumpAndSettle();

    expect(find.text('+100 GEM'), findsOneWidget);
    expect(find.byIcon(Icons.diamond_rounded), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
