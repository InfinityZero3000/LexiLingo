import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';

void main() {
  group('Fill-in-the-blank Formatter Tests', () {
    test('Should return unchanged question if {blank} token is not present', () {
      final question = 'What is your name?';
      final answer = 'John';
      final result = formatFillBlankPrompt(question, answer);
      expect(result, equals('What is your name?'));
    });

    test('Should format a single word blank correctly', () {
      final question = 'The cat sat on the {blank}.';
      final answer = 'mat';
      final result = formatFillBlankPrompt(question, answer);
      expect(result, equals('The cat sat on the ___.'));
    });

    test('Should format multiple word blanks correctly with corresponding spaces', () {
      final question = 'She {blank} to the market yesterday.';
      final answer = 'has gone';
      final result = formatFillBlankPrompt(question, answer);
      expect(result, equals('She ___ ____ to the market yesterday.'));
    });

    test('Should handle special characters inside the correct answer length matching', () {
      final question = 'We need to discuss the {blank}.';
      final answer = 'check-in';
      final result = formatFillBlankPrompt(question, answer);
      expect(result, equals('We need to discuss the ________.'));
    });
  });
}
