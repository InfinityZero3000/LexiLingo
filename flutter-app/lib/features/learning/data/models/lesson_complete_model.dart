import 'package:lexilingo_app/features/learning/domain/entities/lesson_complete.dart';

/// Lesson Complete Model
/// Represents response from POST /learning/attempts/{id}/complete
class LessonCompleteModel extends LessonComplete {
  const LessonCompleteModel({
    required super.attemptId,
    required super.passed,
    required super.finalScore,
    required super.totalXpEarned,
    required super.timeSpentSeconds,
    required super.accuracy,
    required super.starsEarned,
    super.nextLessonUnlocked,
    required super.achievementsUnlocked,
    required super.totalQuestions,
    required super.correctAnswers,
    required super.wrongAnswers,
    required super.hintsUsed,
  });

  factory LessonCompleteModel.fromJson(Map<String, dynamic> json) {
    return LessonCompleteModel(
      attemptId: json['attempt_id'] as String,
      passed: json['passed'] as bool,
      finalScore: (json['final_score'] as num).toDouble(),
      totalXpEarned: json['total_xp_earned'] as int? ?? 0,
      timeSpentSeconds: json['time_spent_seconds'] as int? ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      starsEarned: json['stars_earned'] as int? ?? 0,
      nextLessonUnlocked: json['next_lesson_unlocked'] as String?,
      achievementsUnlocked:
          (json['achievements_unlocked'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      totalQuestions: json['total_questions'] as int? ?? 0,
      correctAnswers: json['correct_answers'] as int? ?? 0,
      wrongAnswers: json['wrong_answers'] as int? ?? 0,
      hintsUsed: json['hints_used'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'attempt_id': attemptId,
      'passed': passed,
      'final_score': finalScore,
      'total_xp_earned': totalXpEarned,
      'time_spent_seconds': timeSpentSeconds,
      'accuracy': accuracy,
      'stars_earned': starsEarned,
      'next_lesson_unlocked': nextLessonUnlocked,
      'achievements_unlocked': achievementsUnlocked,
      'total_questions': totalQuestions,
      'correct_answers': correctAnswers,
      'wrong_answers': wrongAnswers,
      'hints_used': hintsUsed,
    };
  }
}
