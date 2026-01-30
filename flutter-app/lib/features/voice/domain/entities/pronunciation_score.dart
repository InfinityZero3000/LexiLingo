import 'package:equatable/equatable.dart';

/// Pronunciation assessment result
/// Scores the user's pronunciation against the target
class PronunciationScore extends Equatable {
  final int overallScore;       // 0-100
  final int accuracyScore;      // 0-100
  final int fluencyScore;       // 0-100
  final int completenessScore;  // 0-100
  final String userTranscript;
  final String targetText;
  final List<WordScore> wordScores;
  final String? feedback;

  const PronunciationScore({
    required this.overallScore,
    required this.accuracyScore,
    required this.fluencyScore,
    required this.completenessScore,
    required this.userTranscript,
    required this.targetText,
    this.wordScores = const [],
    this.feedback,
  });

  bool get isExcellent => overallScore >= 90;
  bool get isGood => overallScore >= 70 && overallScore < 90;
  bool get isNeedsWork => overallScore < 70;

  String get grade {
    if (overallScore >= 90) return 'A';
    if (overallScore >= 80) return 'B';
    if (overallScore >= 70) return 'C';
    if (overallScore >= 60) return 'D';
    return 'F';
  }

  @override
  List<Object?> get props => [
        overallScore,
        accuracyScore,
        fluencyScore,
        completenessScore,
        userTranscript,
        targetText,
        wordScores,
        feedback,
      ];
}

/// Individual word pronunciation score
class WordScore extends Equatable {
  final String word;
  final int score;
  final String? phonemes;
  final String? issue; // e.g., "mispronunciation", "omission", "insertion"

  const WordScore({
    required this.word,
    required this.score,
    this.phonemes,
    this.issue,
  });

  bool get hasIssue => issue != null && issue!.isNotEmpty;

  @override
  List<Object?> get props => [word, score, phonemes, issue];
}
