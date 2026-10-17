import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';

/// Regression test: tapping one word/pair used to call onAnswer directly,
/// which the provider treats as a final submit — locking the exercise
/// (isAnswered) and disabling every remaining tile after the first tap.
/// These widgets must report in-progress picks via onInputChanged (a draft)
/// and never call onAnswer themselves.
void main() {
  testWidgets('ArrangeSentenceWidget drafts each word, never self-submits', (
    tester,
  ) async {
    final exercise = Exercise(
      id: 'arrange-1',
      type: ExerciseType.reorder,
      uiType: 'arrange_the_sentence',
      question: 'Arrange: morning / every / reads / she / the / newspaper',
      options: const ['she', 'reads', 'the', 'newspaper', 'every', 'morning'],
      correctAnswer: 'she reads the newspaper every morning',
    );

    var onAnswerCalls = 0;
    final drafts = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArrangeSentenceWidget(
            exercise: exercise,
            onAnswer: (_) => onAnswerCalls++,
            onInputChanged: drafts.add,
            isAnswered: false,
          ),
        ),
      ),
    );

    await tester.tap(find.text('reads'));
    await tester.pump();
    expect(onAnswerCalls, 0);
    expect(drafts.last, 'reads');

    // The bank word must still be tappable after the first pick.
    await tester.tap(find.text('she'));
    await tester.pump();
    expect(onAnswerCalls, 0);
    expect(drafts.last, 'reads she');
  });

  testWidgets('MatchWordMeaningWidget drafts each pair, never self-submits', (
    tester,
  ) async {
    final exercise = Exercise(
      id: 'match-1',
      type: ExerciseType.matching,
      uiType: 'match_word_to_meaning',
      question: 'Match the words with their meanings',
      options: const ['one', 'two', 'một', 'hai'],
      correctAnswer: 'one:một, two:hai',
    );

    var onAnswerCalls = 0;
    final drafts = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchWordMeaningWidget(
            exercise: exercise,
            onAnswer: (_) => onAnswerCalls++,
            onInputChanged: drafts.add,
            isAnswered: false,
          ),
        ),
      ),
    );

    await tester.tap(find.text('one'));
    await tester.pump();
    await tester.tap(find.text('một'));
    await tester.pump();
    expect(onAnswerCalls, 0);
    expect(drafts.last, 'one:một');

    // The second pair must still be tappable after the first match.
    await tester.tap(find.text('two'));
    await tester.pump();
    await tester.tap(find.text('hai'));
    await tester.pump();
    expect(onAnswerCalls, 0);
    expect(drafts.last, 'one:một, two:hai');
  });
}
