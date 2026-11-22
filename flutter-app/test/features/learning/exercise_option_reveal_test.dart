import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

Color _fill(WidgetTester tester, String text) {
  final box = tester.widget<AnimatedContainer>(
    find.ancestor(
      of: find.text(text),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  Widget host({required bool light}) => MaterialApp(
    theme: ThemeData(
      brightness: light ? Brightness.light : Brightness.dark,
      extensions: [light ? AppStatusColors.light : AppStatusColors.dark],
    ),
    home: Scaffold(
      body: Column(
        children: [
          ExerciseOptionCard(
            text: 'picked',
            isSelected: true,
            isCorrect: false,
            isAnswered: true,
          ),
          ExerciseOptionCard(
            text: 'right',
            isSelected: false,
            isCorrect: true,
            isAnswered: true,
          ),
          ExerciseOptionCard(
            text: 'other',
            isSelected: false,
            isCorrect: false,
            isAnswered: true,
          ),
        ],
      ),
    ),
  );

  for (final light in [true, false]) {
    testWidgets('a wrong pick reveals the correct option (light=$light)', (
      tester,
    ) async {
      await tester.pumpWidget(host(light: light));
      final scheme = Theme.of(tester.element(find.text('picked'))).colorScheme;
      final status = light ? AppStatusColors.light : AppStatusColors.dark;

      expect(_fill(tester, 'picked'), scheme.error);
      expect(_fill(tester, 'right'), status.success);
      expect(_fill(tester, 'other'), isNot(status.success));
      expect(_fill(tester, 'other'), isNot(scheme.error));
    });
  }
}
