import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/short_writing_answer_widget.dart';

Exercise _ex(String question) => Exercise(
  id: 'w1',
  type: ExerciseType.translate,
  uiType: 'short_writing_answer',
  phase: 'production',
  question: question,
  correctAnswer: 'Hello',
);

/// What the learner reads: every text span of the question, in order.
String _questionText(WidgetTester tester) {
  final rich = tester.widgetList<RichText>(find.byType(RichText)).firstWhere(
    (r) => r.text.toPlainText().startsWith('Write'),
  );
  return rich.text.toPlainText();
}

Future<void> _pump(WidgetTester tester, String question) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ShortWritingAnswerWidget(
        exercise: _ex(question),
        onAnswer: (_) {},
        isAnswered: false,
      ),
    ),
  ),
);

void main() {
  setUp(() => EasyLocalization.logger.enableLevels = []);

  group('splitAroundQuote', () {
    test('keeps the punctuation that follows the closing quote', () {
      final parts = splitAroundQuote('Write in English: "Xin chào".')!;

      expect(parts.before, 'Write in English: ');
      expect(parts.quoted, 'Xin chào');
      expect(parts.after, '.');
    });

    test('single quotes win over double, like extractQuotedWord', () {
      final parts = splitAroundQuote('Say \'hi\' or "hello"')!;

      expect(parts.quoted, 'hi');
    });

    test('no quotes means nothing to highlight', () {
      expect(splitAroundQuote('Describe your day.'), isNull);
    });
  });

  group('ShortWritingAnswerWidget question', () {
    for (final entry in {
      'Write in English: "Xin chào, chào buổi sáng".':
          'Write in English: "Xin chào, chào buổi sáng".',
      "Write in English: 'Cô ấy nói tiếng Anh.'":
          'Write in English: "Cô ấy nói tiếng Anh."',
      'Write a sentence with the idiom \'heart of gold\' to describe a kind person.':
          'Write a sentence with the idiom "heart of gold" to describe a kind person.',
      'Write about your weekend.': 'Write about your weekend.',
    }.entries) {
      testWidgets('reads cleanly: ${entry.key}', (tester) async {
        await _pump(tester, entry.key);

        expect(_questionText(tester), entry.value);
      });
    }

    testWidgets('never shows a stray full stop before the quoted phrase', (
      tester,
    ) async {
      await _pump(tester, 'Write in English: "Xin chào, chào buổi sáng".');

      expect(_questionText(tester), isNot(contains(': .')));
    });
  });
}
