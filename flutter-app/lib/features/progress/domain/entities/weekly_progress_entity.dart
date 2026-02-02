/// Weekly Progress Entity
/// 
/// Following agent-skills/language-learning-patterns:
/// - progress-learning-streaks: Visual progress tracking (3-5x engagement boost)
/// 
/// Used for home page week progress chart.
library;

import 'package:equatable/equatable.dart';

/// Single day's progress data
class DailyProgressEntity extends Equatable {
  final String day;           // Mon, Tue, Wed, etc.
  final DateTime date;
  final int xpEarned;
  final int lessonsCompleted;
  final int studyTimeMinutes;
  final int vocabularyReviewed;
  final bool goalMet;
  final bool isToday;

  const DailyProgressEntity({
    required this.day,
    required this.date,
    required this.xpEarned,
    required this.lessonsCompleted,
    required this.studyTimeMinutes,
    required this.vocabularyReviewed,
    required this.goalMet,
    required this.isToday,
  });

  /// Create empty day placeholder
  factory DailyProgressEntity.empty(String day, DateTime date) {
    return DailyProgressEntity(
      day: day,
      date: date,
      xpEarned: 0,
      lessonsCompleted: 0,
      studyTimeMinutes: 0,
      vocabularyReviewed: 0,
      goalMet: false,
      isToday: false,
    );
  }

  /// Check if day has any activity
  bool get hasActivity => xpEarned > 0 || lessonsCompleted > 0;

  /// Progress percentage for visual display (0.0 - 1.0)
  double get progressPercentage {
    const targetXP = 20; // Daily goal
    return (xpEarned / targetXP).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [
        day,
        date,
        xpEarned,
        lessonsCompleted,
        studyTimeMinutes,
        vocabularyReviewed,
        goalMet,
        isToday,
      ];
}

/// Weekly progress summary
class WeeklyProgressEntity extends Equatable {
  final List<DailyProgressEntity> weekProgress;
  final int totalXP;
  final int totalLessons;
  final int totalStudyTime;
  final int daysActive;
  final int currentStreak;
  final int longestStreak;
  final double weekGoalProgress;

  const WeeklyProgressEntity({
    required this.weekProgress,
    required this.totalXP,
    required this.totalLessons,
    required this.totalStudyTime,
    required this.daysActive,
    required this.currentStreak,
    required this.longestStreak,
    required this.weekGoalProgress,
  });

  /// Create empty/default weekly progress
  factory WeeklyProgressEntity.empty() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: 6));
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    
    return WeeklyProgressEntity(
      weekProgress: List.generate(7, (i) {
        final date = weekStart.add(Duration(days: i));
        return DailyProgressEntity.empty(
          dayNames[date.weekday - 1],
          date,
        );
      }),
      totalXP: 0,
      totalLessons: 0,
      totalStudyTime: 0,
      daysActive: 0,
      currentStreak: 0,
      longestStreak: 0,
      weekGoalProgress: 0.0,
    );
  }

  /// Get today's progress
  DailyProgressEntity? get todayProgress {
    try {
      return weekProgress.firstWhere((d) => d.isToday);
    } catch (_) {
      return null;
    }
  }

  /// Get max XP earned in a single day (for chart scaling)
  int get maxDailyXP {
    if (weekProgress.isEmpty) return 20;
    final max = weekProgress.map((d) => d.xpEarned).reduce((a, b) => a > b ? a : b);
    return max > 0 ? max : 20;
  }

  /// Get active days percentage
  double get activeDaysPercentage => daysActive / 7;

  /// Check if user is on track (at least 4 days active)
  bool get isOnTrack => daysActive >= 4;

  @override
  List<Object?> get props => [
        weekProgress,
        totalXP,
        totalLessons,
        totalStudyTime,
        daysActive,
        currentStreak,
        longestStreak,
        weekGoalProgress,
      ];
}
