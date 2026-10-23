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
    expect(drafts.last, '');

    // The bank word must still be tappable after the first pick.
    await tester.tap(find.text('she'));
    await tester.pump();
    expect(onAnswerCalls, 0);
    // Half a sentence is not an answer — the check button must stay off.
    expect(drafts.last, '');

    for (final w in ['the', 'newspaper', 'every', 'morning']) {
      await tester.tap(find.text(w));
      await tester.pump();
    }
    expect(onAnswerCalls, 0);
    expect(drafts.last, 'reads she the newspaper every morning');
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
    // One of two pairs is not an answer yet — the check button must stay off.
    expect(drafts.last, '');

    // The second pair must still be tappable after the first match.
    await tester.tap(find.text('two'));
    await tester.pump();
    await tester.tap(find.text('hai'));
    await tester.pump();
    expect(onAnswerCalls, 0);
    expect(drafts.last, 'one:một, two:hai');

    // A wrong match must be undoable: tapping a matched word frees the pair
    // and the draft drops back to "not an answer".
    await tester.tap(find.text('two'));
    await tester.pump();
    expect(drafts.last, '');
    await tester.tap(find.text('two'));
    await tester.pump();
    await tester.tap(find.text('hai'));
    await tester.pump();
    expect(drafts.last, 'one:một, two:hai');
    expect(onAnswerCalls, 0);
  });

  testWidgets('CategorizationWidget shows one bucket per category', (
    tester,
  ) async {
    // Stored one category per word, so "fruit" appears twice.
    final exercise = Exercise(
      id: 'cat-1',
      type: ExerciseType.matching,
      uiType: 'categorization',
      question: 'Sort the words',
      options: const ['apple', 'pear', 'dog', 'fruit', 'fruit', 'animal'],
      correctAnswer: 'apple:fruit, pear:fruit, dog:animal',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategorizationWidget(
            exercise: exercise,
            onAnswer: (_) {},
            onInputChanged: (_) {},
            isAnswered: false,
          ),
        ),
      ),
    );

    expect(find.text('FRUIT'), findsOneWidget);
    expect(find.text('ANIMAL'), findsOneWidget);
  });
}
