import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';

/// Stored content keeps the pairs aligned (first half keys, second half
/// values). If the right column renders in that stored order the exercise is
/// solvable by tapping row i ↔ row i without reading anything.
void main() {
  const keys = ['one', 'two', 'three', 'four', 'five', 'six'];
  const values = ['một', 'hai', 'ba', 'bốn', 'năm', 'sáu'];

  Exercise exerciseWithId(String id) => Exercise(
    id: id,
    type: ExerciseType.matching,
    uiType: 'match_word_to_meaning',
    question: 'Match the words with their meanings',
    options: [...keys, ...values],
    correctAnswer: [
      for (var i = 0; i < keys.length; i++) '${keys[i]}:${values[i]}',
    ].join(', '),
  );

  Future<List<String>> renderedTexts(WidgetTester tester, Exercise e) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchWordMeaningWidget(
            exercise: e,
            onAnswer: (_) {},
            isAnswered: false,
          ),
        ),
      ),
    );
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) => keys.contains(t) || values.contains(t))
        .toList();
  }

  testWidgets('right column is shuffled, left column is not', (tester) async {
    // Deterministic per id, so try a few ids: none of them may render the
    // values in stored order.
    var shuffledAtLeastOnce = false;
    for (final id in ['ex-1', 'ex-2', 'ex-3']) {
      final texts = await renderedTexts(tester, exerciseWithId(id));

      // Rows interleave the columns, so read each column by its own words.
      expect(texts.where(keys.contains), keys);
      final right = texts.where(values.contains).toList();
      expect(right.toSet(), values.toSet());
      if (right.join('|') != values.join('|')) shuffledAtLeastOnce = true;
    }
    expect(shuffledAtLeastOnce, isTrue);
  });

  testWidgets('same exercise keeps the same order across rebuilds', (
    tester,
  ) async {
    final exercise = exerciseWithId('stable-id');
    final first = await renderedTexts(tester, exercise);
    await tester.pump();
    final second = await renderedTexts(tester, exercise);

    expect(second, first);
  });

  testWidgets('a screen reader can pair the words', (tester) async {
    final semantics = tester.ensureSemantics();
    await renderedTexts(tester, exerciseWithId('a11y'));

    for (final word in [keys.first, values.first]) {
      tester.semantics.tap(find.semantics.byLabel(word));
      await tester.pump();
    }

    expect(
      tester.getSemantics(find.bySemanticsLabel(keys.first)),
      matchesSemantics(
        label: keys.first,
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}
