import 'package:lexilingo_app/features/learning/domain/entities/lesson_attempt.dart';

/// Lesson Attempt Model
/// Represents response from POST /learning/lessons/{id}/start
class LessonAttemptModel extends LessonAttempt {
  const LessonAttemptModel({
    required super.attemptId,
    required super.lessonId,
    required super.startedAt,
    required super.totalQuestions,
    required super.livesRemaining,
    required super.hintsAvailable,
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
