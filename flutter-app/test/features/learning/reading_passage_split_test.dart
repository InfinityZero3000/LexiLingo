import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';

void main() {
  testWidgets('a quoted passage is not cut into the question', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingComprehensionWidget(
            exercise: Exercise(
              id: 'read',
              type: ExerciseType.multipleChoice,
              uiType: 'reading_comprehension',
              question:
                  "Read and answer: 'Tom is a chef. He works in a "
                  "restaurant.' Where does Tom work?",
              options: const ['restaurant', 'office'],
              correctAnswer: 'restaurant',
            ),
            onAnswer: (_) {},
            isAnswered: false,
          ),
        ),
      ),
    );

    expect(find.text('Where does Tom work?'), findsOneWidget);
    expect(
      find.text("Read and answer: 'Tom is a chef. He works in a restaurant.'"),
      findsOneWidget,
    );
  });
}
