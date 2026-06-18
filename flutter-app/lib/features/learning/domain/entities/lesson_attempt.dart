class LessonAttempt {
  final String attemptId;
  final String lessonId;
  final DateTime startedAt;
  final int totalQuestions;
  final int livesRemaining;
  final int hintsAvailable;

  const LessonAttempt({
    required this.attemptId,
    required this.lessonId,
    required this.startedAt,
    required this.totalQuestions,
    required this.livesRemaining,
    required this.hintsAvailable,
  });
}
