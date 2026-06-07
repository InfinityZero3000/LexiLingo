import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';

void main() {
  final exercise = Exercise(
    id: 'theme-exercise',
    type: ExerciseType.trueFalse,
    question: 'Flutter can render light and dark themes.',
    correctAnswer: 'True',
  );

  Future<void> pumpExercise(
    WidgetTester tester, {
    required ThemeData theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: TrueOrFalseWidget(
            exercise: exercise,
            onAnswer: (_) {},
            isAnswered: false,
          ),
        ),
      ),
    );
  }

  Iterable<Color?> decorationColors(WidgetTester tester) {
    return tester.widgetList<Container>(find.byType(Container)).map((
      container,
    ) {
      final decoration = container.decoration;
      return decoration is BoxDecoration ? decoration.color : null;
    });
  }

  testWidgets('uses light semantic surfaces in light mode', (tester) async {
    await pumpExercise(tester, theme: AppTheme.lightTheme);

    expect(decorationColors(tester), contains(AppColors.surfaceLight));
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.style?.color),
      contains(AppColors.textDark),
    );
  });

  testWidgets('uses dark semantic surfaces and text in dark mode', (
    tester,
  ) async {
    await pumpExercise(tester, theme: AppTheme.darkTheme);

    expect(decorationColors(tester), contains(AppColors.surfaceDark));
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.style?.color),
      contains(AppColors.textOnDarkPrimary),
    );
  });
}
