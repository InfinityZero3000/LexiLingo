import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/services/speaking_answer_matcher.dart';

void main() {
  group('SpeakingAnswerMatcher', () {
    test('normalizes punctuation, case, and repeated whitespace', () {
      expect(
        SpeakingAnswerMatcher.normalize('  Could YOU, please speak slowly?  '),
        'could you please speak slowly',
      );
    });

    test('approves an exact normalized sentence', () {
      final result = SpeakingAnswerMatcher.evaluate(
        transcript: 'Could you please speak more slowly?',
        target: 'Could you please speak more slowly?',
      );

      expect(result.isApproved, isTrue);
      expect(result.similarity, 1);
    });

    test('approves a minor recognition difference', () {
      final result = SpeakingAnswerMatcher.evaluate(
        transcript: 'Could you please speak more slow',
        target: 'Could you please speak more slowly',
      );

      expect(result.isApproved, isTrue);
      expect(result.similarity, greaterThanOrEqualTo(0.85));
    });

    test('rejects a substantially different sentence', () {
      final result = SpeakingAnswerMatcher.evaluate(
        transcript: 'What time does the train leave',
        target: 'Could you please speak more slowly',
      );

      expect(result.isApproved, isFalse);
      expect(result.similarity, lessThan(0.85));
    });

    test('rejects an empty transcript', () {
      final result = SpeakingAnswerMatcher.evaluate(
        transcript: '   ',
        target: 'Could you please speak more slowly',
      );

      expect(result.isApproved, isFalse);
      expect(result.similarity, 0);
    });
  });
}
