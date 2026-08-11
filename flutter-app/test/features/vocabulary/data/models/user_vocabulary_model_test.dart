import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/vocabulary/data/models/user_vocabulary_model.dart';

void main() {
  group('UserVocabularyModel.fromJson', () {
    Map<String, dynamic> baseJson({Map<String, dynamic>? vocabulary}) => {
      'id': 'uv-1',
      'user_id': 'user-1',
      'vocabulary_id': 'vocab-1',
      'status': 'learning',
      'ease_factor': 2.5,
      'interval': 1,
      'repetitions': 0,
      'next_review_date': '2026-01-01T00:00:00Z',
      'added_at': '2026-01-01T00:00:00Z',
      if (vocabulary != null) 'vocabulary': vocabulary,
    };

    test('reads word from the nested vocabulary item', () {
      final model = UserVocabularyModel.fromJson(
        baseJson(vocabulary: {'word': 'Serendipity'}),
      );

      expect(model.word, 'Serendipity');
    });

    test('leaves word null when the backend omits the nested item', () {
      final model = UserVocabularyModel.fromJson(baseJson());

      expect(model.word, isNull);
    });
  });
}
