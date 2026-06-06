import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';

void main() {
  testWidgets('blank can be tapped, focused, and edited', (tester) async {
    String? draftAnswer;
    final exercise = Exercise(
      id: 'dialogue-1',
      type: ExerciseType.fillInBlank,
      uiType: 'dialogue_completion',
      question:
          'A: What do you do for a living? B: I {blank} as an engineer.',
      correctAnswer: 'work',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogueCompletionWidget(
            exercise: exercise,
            onAnswer: (_) {},
            onInputChanged: (value) => draftAnswer = value,
            isAnswered: false,
          ),
        ),
      ),
    );

    final input = find.byKey(const Key('dialogue-blank-input'));
    expect(input, findsOneWidget);

    await tester.tap(input);
    await tester.pump();

    final editableText = tester.widget<EditableText>(
      find.descendant(of: input, matching: find.byType(EditableText)),
    );
    expect(editableText.focusNode.hasFocus, isTrue);

    await tester.enterText(input, 'work');
    await tester.pump();

    expect(draftAnswer, 'work');
    expect(find.text('work'), findsOneWidget);
  });
}
