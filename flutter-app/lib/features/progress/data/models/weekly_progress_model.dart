/// Weekly Progress Model
/// 
/// Data layer model for weekly progress API response.
/// Maps to WeeklyProgressEntity.
library;

import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';

/// Model for daily progress data from API
class DailyProgressModel extends DailyProgressEntity {
  const DailyProgressModel({
    required super.day,
    required super.date,
    required super.xpEarned,
    required super.lessonsCompleted,
    required super.studyTimeMinutes,
    required super.vocabularyReviewed,
    required super.goalMet,
    required super.isToday,
  });

  factory DailyProgressModel.fromJson(Map<String, dynamic> json) {
    return DailyProgressModel(
      day: json['day_name'] as String? ?? json['day'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      xpEarned: json['xp_earned'] as int? ?? 0,
      lessonsCompleted: json['lessons_completed'] as int? ?? 0,
      studyTimeMinutes: json['study_time_minutes'] as int? ?? 0,
      vocabularyReviewed: json['vocabulary_reviewed'] as int? ?? 0,
      goalMet: json['daily_goal_met'] as bool? ?? json['goal_met'] as bool? ?? false,
      isToday: json['is_today'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'date': date.toIso8601String().split('T')[0],
      'xp_earned': xpEarned,
      'lessons_completed': lessonsCompleted,
      'study_time_minutes': studyTimeMinutes,
      'vocabulary_reviewed': vocabularyReviewed,
      'goal_met': goalMet,
      'is_today': isToday,
    };
  }

  DailyProgressEntity toEntity() => this;

  factory DailyProgressModel.fromEntity(DailyProgressEntity entity) {
    return DailyProgressModel(
      day: entity.day,
      date: entity.date,
      xpEarned: entity.xpEarned,
      lessonsCompleted: entity.lessonsCompleted,
      studyTimeMinutes: entity.studyTimeMinutes,
      vocabularyReviewed: entity.vocabularyReviewed,
      goalMet: entity.goalMet,
      isToday: entity.isToday,
    );
  }
}

/// Model for weekly progress response from API
class WeeklyProgressModel extends WeeklyProgressEntity {
  const WeeklyProgressModel({
    required List<DailyProgressEntity> weekProgress,
    required super.totalXP,
    required super.totalLessons,
    required super.totalStudyTime,
    required super.daysActive,
    required super.currentStreak,
    required super.longestStreak,
    required super.weekGoalProgress,
  }) : super(weekProgress: weekProgress);

  factory WeeklyProgressModel.fromJson(Map<String, dynamic> json) {
    // Support both 'days' (new API) and 'week_progress' (legacy) format
    final weekProgressJson = json['days'] as List<dynamic>? ?? 
                              json['week_progress'] as List<dynamic>? ?? [];
    
    return WeeklyProgressModel(
      weekProgress: weekProgressJson
          .map((item) => DailyProgressModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalXP: json['total_xp'] as int? ?? 0,
      totalLessons: json['total_lessons'] as int? ?? 0,
      totalStudyTime: json['total_study_time'] as int? ?? 0,
      daysActive: json['days_active'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      weekGoalProgress: (json['week_goal_progress'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'week_progress': weekProgress
          .map((d) => DailyProgressModel.fromEntity(d).toJson())
          .toList(),
      'total_xp': totalXP,
      'total_lessons': totalLessons,
      'total_study_time': totalStudyTime,
      'days_active': daysActive,
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'week_goal_progress': weekGoalProgress,
    };
  }

  WeeklyProgressEntity toEntity() => this;
}
