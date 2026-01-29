/// Lesson Attempt Model
/// Represents response from POST /learning/lessons/{id}/start
class LessonAttemptModel {
  final String attemptId;
  final String lessonId;
  final DateTime startedAt;
  final int totalQuestions;
  final int livesRemaining;
  final int hintsAvailable;

  LessonAttemptModel({
    required this.attemptId,
    required this.lessonId,
    required this.startedAt,
    required this.totalQuestions,
    required this.livesRemaining,
    required this.hintsAvailable,
  });

  factory LessonAttemptModel.fromJson(Map<String, dynamic> json) {
    return LessonAttemptModel(
      attemptId: json['attempt_id'] as String,
      lessonId: json['lesson_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      totalQuestions: json['total_questions'] as int? ?? 10,
      livesRemaining: json['lives_remaining'] as int? ?? 3,
      hintsAvailable: json['hints_available'] as int? ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'attempt_id': attemptId,
      'lesson_id': lessonId,
      'started_at': startedAt.toIso8601String(),
      'total_questions': totalQuestions,
      'lives_remaining': livesRemaining,
      'hints_available': hintsAvailable,
    };
  }
}
