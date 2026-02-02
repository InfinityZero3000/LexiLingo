import 'package:lexilingo_app/features/user/domain/entities/weekly_activity_entity.dart';

/// Weekly Activity Model
class WeeklyActivityModel extends WeeklyActivityEntity {
  const WeeklyActivityModel({
    required super.date,
    required super.xpEarned,
    required super.lessonsCompleted,
    required super.vocabularyLearned,
  });

  factory WeeklyActivityModel.fromJson(Map<String, dynamic> json) {
    return WeeklyActivityModel(
      date: json['date'] as String,
      xpEarned: json['xp_earned'] as int? ?? 0,
      lessonsCompleted: json['lessons_completed'] as int? ?? 0,
      vocabularyLearned: json['vocabulary_learned'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'xp_earned': xpEarned,
      'lessons_completed': lessonsCompleted,
      'vocabulary_learned': vocabularyLearned,
    };
  }
}
