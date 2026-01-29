/// Answer Response Model
/// Represents response from POST /learning/attempts/{id}/answer
class AnswerResponseModel {
  final String questionAttemptId;
  final bool isCorrect;
  final String? correctAnswer;
  final String? explanation;
  final int xpEarned;
  final int livesRemaining;
  final int hintsRemaining;
  final double currentScore;

  AnswerResponseModel({
    required this.questionAttemptId,
    required this.isCorrect,
    this.correctAnswer,
    this.explanation,
    required this.xpEarned,
    required this.livesRemaining,
    required this.hintsRemaining,
    required this.currentScore,
  });

  factory AnswerResponseModel.fromJson(Map<String, dynamic> json) {
    return AnswerResponseModel(
      questionAttemptId: json['question_attempt_id'] as String,
      isCorrect: json['is_correct'] as bool,
      correctAnswer: json['correct_answer'] as String?,
      explanation: json['explanation'] as String?,
      xpEarned: json['xp_earned'] as int? ?? 0,
      livesRemaining: json['lives_remaining'] as int? ?? 3,
      hintsRemaining: json['hints_remaining'] as int? ?? 3,
      currentScore: (json['current_score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question_attempt_id': questionAttemptId,
      'is_correct': isCorrect,
      'correct_answer': correctAnswer,
      'explanation': explanation,
      'xp_earned': xpEarned,
      'lives_remaining': livesRemaining,
      'hints_remaining': hintsRemaining,
      'current_score': currentScore,
    };
  }
}
