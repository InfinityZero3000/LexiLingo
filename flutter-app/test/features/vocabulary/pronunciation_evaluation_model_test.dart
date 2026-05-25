import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/vocabulary/data/models/pronunciation_evaluation_model.dart';

void main() {
  group('PronunciationEvaluationModel', () {
    test('parses backend response and maps high score to perfect review', () {
      final model = PronunciationEvaluationModel.fromJson({
        'vocabulary_id': '00000000-0000-0000-0000-000000000050',
        'target_word': 'religion',
        'score': 86.5,
        'stars': 3,
        'feedback_label': 'Amazing',
        'transcription': 'religion',
        'phoneme_scores': {'overall_confidence': 0.92},
        'errors': [],
        'duration_ms': 42.0,
      });

      expect(model.vocabularyId, '00000000-0000-0000-0000-000000000050');
      expect(model.targetWord, 'religion');
      expect(model.score, 86.5);
      expect(model.stars, 3);
      expect(model.feedbackLabel, 'Amazing');
      expect(model.reviewQuality, 5);
      expect(model.phonemeScores['overall_confidence'], 0.92);
      expect(model.durationMs, 42.0);
    });

    test('maps middle and low scores to speaking review qualities', () {
      final good = PronunciationEvaluationModel.fromJson({
        'vocabulary_id': 'vocab-1',
        'target_word': 'hello',
        'score': 72,
        'stars': 2,
        'feedback_label': 'Good',
      });
      final retry = PronunciationEvaluationModel.fromJson({
        'vocabulary_id': 'vocab-2',
        'target_word': 'hello',
        'score': 41,
        'stars': 1,
        'feedback_label': 'Try again',
      });

      expect(good.reviewQuality, 3);
      expect(retry.reviewQuality, 1);
    });
  });
}
