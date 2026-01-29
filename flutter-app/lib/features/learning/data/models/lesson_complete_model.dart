/// Lesson Complete Model
/// Represents response from POST /learning/attempts/{id}/complete
class LessonCompleteModel {
  final String attemptId;
  final bool passed;
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

  LessonCompleteModel({
    required this.attemptId,
    required this.passed,
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
      achievementsUnlocked: (json['achievements_unlocked'] as List<dynamic>?)
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
