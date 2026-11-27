/// Pass mark assumed when the server does not report the lesson's own.
const int kDefaultLessonPassMark = 80;

class LessonComplete {
  final String attemptId;
  final bool passed;
  final int? passThreshold;
  final double finalScore;
  final int totalXpEarned;
  final int timeSpentSeconds;
  final double accuracy;
  final int starsEarned;
  final String? nextLessonUnlocked;
  final List<String> achievementsUnlocked;
  final int totalQuestions;
  final int correctAnswers;
  final int wrongAnswers;
  final int hintsUsed;

  const LessonComplete({
    required this.attemptId,
    required this.passed,
    this.passThreshold,
    required this.finalScore,
    required this.totalXpEarned,
    required this.timeSpentSeconds,
    required this.accuracy,
    required this.starsEarned,
    this.nextLessonUnlocked,
    required this.achievementsUnlocked,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.hintsUsed,
  });
}
