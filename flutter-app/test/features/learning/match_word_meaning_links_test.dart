import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';

final _exercise = Exercise(
  id: 'm1',
  type: ExerciseType.matching,
  uiType: 'match_word_to_meaning',
  question: 'Match the words with their meanings',
  options: ['Hello', 'Goodbye', 'Xin chào', 'Tạm biệt'],
  correctAnswer: 'Hello:Xin chào, Goodbye:Tạm biệt',
);

void main() {
  setUp(() => EasyLocalization.logger.enableLevels = []);

  Future<List<String>> pump(WidgetTester tester) async {
    final drafts = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchWordMeaningWidget(
            exercise: _exercise,
            onAnswer: (_) {},
            onInputChanged: drafts.add,
            isAnswered: false,
          ),
        ),
      ),
    );
    return drafts;
  }

  testWidgets('a matched pair is drawn as a line and is only an answer once '
      'every pair is matched', (tester) async {
    final drafts = await pump(tester);
    final board = tester
        .renderObjectList<RenderCustomPaint>(find.byType(CustomPaint))
        .firstWhere(
          (r) => r.painter.runtimeType.toString() == '_PairLinkPainter',
        );

    await tester.tap(find.text('Hello'));
    await tester.tap(find.text('Xin chào'));
    await tester.pump();
    expect(board, paints..path());
    expect(drafts.last, isEmpty, reason: 'one of two pairs is not an answer');

    await tester.tap(find.text('Tạm biệt'));
    await tester.tap(find.text('Goodbye'));
    await tester.pump();
    expect(
      board,
      paints
        ..path()
        ..path(),
    );
    expect(_pairs(drafts.last), {'Hello:Xin chào', 'Goodbye:Tạm biệt'});
  });

  testWidgets('either column can be tapped first', (tester) async {
    final drafts = await pump(tester);
    await tester.tap(find.text('Xin chào'));
    await tester.tap(find.text('Hello'));
    await tester.tap(find.text('Goodbye'));
    await tester.tap(find.text('Tạm biệt'));
    await tester.pump();
    expect(_pairs(drafts.last), {'Hello:Xin chào', 'Goodbye:Tạm biệt'});
  });

  testWidgets('tapping a matched word from either side undoes its pair', (
    tester,
  ) async {
    final drafts = await pump(tester);
    for (final t in ['Hello', 'Xin chào', 'Goodbye', 'Tạm biệt']) {
      await tester.tap(find.text(t));
    }
    await tester.pump();
    expect(drafts.last, isNotEmpty);

    await tester.tap(find.text('Xin chào'));
    await tester.pump();
    expect(drafts.last, isEmpty);

    await tester.tap(find.text('Hello'));
    await tester.tap(find.text('Xin chào'));
    await tester.pump();
    expect(_pairs(drafts.last), {'Hello:Xin chào', 'Goodbye:Tạm biệt'});
  });
}

// The grader reads pairs, not their order; only what is paired matters.
Set<String> _pairs(String answer) => answer.split(', ').toSet();
