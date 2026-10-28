import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/lesson_exercises/presentation/lesson_exercises_screen.dart';

void main() {
  test('arrange bank is the sentence words, shuffled, without punctuation', () {
    const sentence = 'She reads the newspaper every morning.';
    final bank = arrangeBankFor(sentence, 7);

    expect(
      [...bank]..sort(),
      ['She', 'every', 'morning', 'newspaper', 'reads', 'the']..sort(),
    );
    expect(bank.join(' '), isNot('She reads the newspaper every morning'));
  });

  test('a one-word sentence still yields its tile', () {
    expect(arrangeBankFor('Hello!', 1), ['Hello']);
  });
}
