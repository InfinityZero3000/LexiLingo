import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';

void main() {
  final translation = {
    'vi': 'đại diện',
    'en': 'a person who represents a group',
    'definitions': {'vi': 'một người đại diện cho một nhóm'},
    'examples': ['She is our representative.'],
  };

  test('keeps the learner-language gloss and definition', () {
    final word = VocabWord(
      word: 'representative',
      definition: 'a person who represents a group',
      translation: translation,
    );

    expect(word.gloss('vi'), 'đại diện');
    expect(word.definitionIn('vi'), 'một người đại diện cho một nhóm');
  });

  test('does not show the English definition again as a translation', () {
    final word = VocabWord(
      word: 'representative',
      definition: 'a person who represents a group',
      translation: translation,
    );

    expect(word.gloss('de'), isNull);
  });

  test('a word saved without a translation has none to show', () {
    final word = VocabWord(word: 'x', definition: 'y');

    expect(word.gloss('vi'), isNull);
    expect(word.definitionIn('vi'), isNull);
  });
}
