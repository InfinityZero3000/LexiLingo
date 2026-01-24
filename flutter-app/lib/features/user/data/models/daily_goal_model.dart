import '../../domain/entities/daily_goal.dart';

class DailyGoalModel extends DailyGoal {
  const DailyGoalModel({
    required super.id,
    required super.userId,
    required super.date,
    super.targetXP,
    super.earnedXP,
    super.lessonsCompleted,
    super.wordsLearned,
    super.minutesSpent,
  });

  factory DailyGoalModel.fromJson(Map<String, dynamic> json) {
    return DailyGoalModel(
      id: json['id'] as int,
      userId: json['userId'] as String,
      date: DateTime.parse(json['date'] as String),
      targetXP: json['targetXP'] as int? ?? 50,
      earnedXP: json['earnedXP'] as int? ?? 0,
      lessonsCompleted: json['lessonsCompleted'] as int? ?? 0,
      wordsLearned: json['wordsLearned'] as int? ?? 0,
      minutesSpent: json['minutesSpent'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'targetXP': targetXP,
      'earnedXP': earnedXP,
      'lessonsCompleted': lessonsCompleted,
      'wordsLearned': wordsLearned,
      'minutesSpent': minutesSpent,
    };
  }

  factory DailyGoalModel.fromEntity(DailyGoal goal) {
    return DailyGoalModel(
      id: goal.id,
      userId: goal.userId,
      date: goal.date,
      targetXP: goal.targetXP,
      earnedXP: goal.earnedXP,
      lessonsCompleted: goal.lessonsCompleted,
      wordsLearned: goal.wordsLearned,
      minutesSpent: goal.minutesSpent,
    );
  }
}
