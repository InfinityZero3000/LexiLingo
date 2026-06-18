class AnswerResponse {
  final String questionAttemptId;
  final bool isCorrect;
  final String? correctAnswer;
  final String? explanation;
  final int xpEarned;
  final int livesRemaining;
  final int hintsRemaining;
  final double currentScore;

  const AnswerResponse({
    required this.questionAttemptId,
    required this.isCorrect,
    this.correctAnswer,
    this.explanation,
    required this.xpEarned,
    required this.livesRemaining,
    required this.hintsRemaining,
    required this.currentScore,
  });
}
