import 'package:lexilingo_app/features/vocabulary/domain/entities/pronunciation_evaluation_entity.dart';

/// Data model for backend pronunciation evaluation response.
class PronunciationEvaluationModel extends PronunciationEvaluationEntity {
  const PronunciationEvaluationModel({
    required super.vocabularyId,
    required super.targetWord,
    required super.score,
    required super.stars,
    required super.feedbackLabel,
    super.transcription,
    super.phonemeScores,
    super.errors,
    super.durationMs,
  });

  factory PronunciationEvaluationModel.fromJson(Map<String, dynamic> json) {
    final rawScores = json['phoneme_scores'];
    final scores = <String, double>{};
    if (rawScores is Map<String, dynamic>) {
      rawScores.forEach((key, value) {
        if (value is num) scores[key] = value.toDouble();
      });
    }

    final rawErrors = json['errors'];
    final errors = rawErrors is List
        ? rawErrors
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];

    return PronunciationEvaluationModel(
      vocabularyId: json['vocabulary_id'] as String,
      targetWord: json['target_word'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      stars: json['stars'] as int? ?? 1,
      feedbackLabel: json['feedback_label'] as String? ?? 'Try again',
      transcription: json['transcription'] as String?,
      phonemeScores: scores,
      errors: errors,
      durationMs: (json['duration_ms'] as num?)?.toDouble(),
    );
  }
}
