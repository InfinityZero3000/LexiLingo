import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';

VocabularyItemEntity _word(Map<String, dynamic>? translation) =>
    VocabularyItemEntity(
      id: '1',
      word: 'drag',
      definition: 'to pull or move something with force',
      translation: translation,
      partOfSpeech: 'noun',
      difficultyLevel: 'A2',
      createdAt: DateTime(2026),
    );

void main() {
  group('getTranslation', () {
    test('returns the exact locale match', () {
      expect(_word({'vi': 'kéo', 'fr': 'traîner'}).getTranslation('fr'),
          'traîner');
    });

    test('falls back to English when the locale is missing', () {
      expect(_word({'vi': 'kéo', 'en': 'to haul'}).getTranslation('ja'),
          'to haul');
    });

    test('never leaks Vietnamese to other locales', () {
      expect(_word({'vi': 'kéo'}).getTranslation('fr'), isNull);
      expect(_word({'vi': 'kéo'}).getTranslation('en'), isNull);
      expect(_word({'vi': 'kéo'}).getTranslation('vi'), 'kéo');
    });

    test('treats empty and absent translations alike', () {
      expect(_word({'vi': ''}).getTranslation('vi'), isNull);
      expect(_word(null).getTranslation('vi'), isNull);
    });
  });
}
