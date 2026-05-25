/// Pronunciation evaluation result for a vocabulary speaking attempt.
class PronunciationEvaluationEntity {
  final String vocabularyId;
  final String targetWord;
  final double score;
  final int stars;
  final String feedbackLabel;
  final String? transcription;
  final Map<String, double> phonemeScores;
  final List<Map<String, dynamic>> errors;
  final double? durationMs;

  const PronunciationEvaluationEntity({
    required this.vocabularyId,
    required this.targetWord,
    required this.score,
    required this.stars,
    required this.feedbackLabel,
    this.transcription,
    this.phonemeScores = const {},
    this.errors = const [],
    this.durationMs,
  });

  int get reviewQuality {
    if (score >= 80) return 5;
    if (score >= 60) return 3;
    return 1;
  }
}
