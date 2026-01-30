import '../../domain/entities/streak_entity.dart';

/// Streak Model
/// Data layer model for API communication
/// Clean Architecture: Maps JSON to Domain Entity
class StreakModel extends StreakEntity {
  const StreakModel({
    required super.currentStreak,
    required super.longestStreak,
    required super.totalDaysActive,
    super.lastActivityDate,
    required super.freezeCount,
    required super.isActiveToday,
    required super.streakAtRisk,
  });

  /// Factory constructor from JSON (API response)
  factory StreakModel.fromJson(Map<String, dynamic> json) {
    return StreakModel(
      currentStreak: json['current_streak'] ?? 0,
      longestStreak: json['longest_streak'] ?? 0,
      totalDaysActive: json['total_days_active'] ?? 0,
      lastActivityDate: json['last_activity_date'],
      freezeCount: json['freeze_count'] ?? 0,
      isActiveToday: json['is_active_today'] ?? false,
      streakAtRisk: json['streak_at_risk'] ?? false,
    );
  }

  /// Convert to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'total_days_active': totalDaysActive,
      'last_activity_date': lastActivityDate,
      'freeze_count': freezeCount,
      'is_active_today': isActiveToday,
      'streak_at_risk': streakAtRisk,
    };
  }

  /// Convert to domain entity
  StreakEntity toEntity() {
    return StreakEntity(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalDaysActive: totalDaysActive,
      lastActivityDate: lastActivityDate,
      freezeCount: freezeCount,
      isActiveToday: isActiveToday,
      streakAtRisk: streakAtRisk,
    );
  }
}

/// Streak Update Result Model
/// Data layer model for streak update API response
class StreakUpdateResultModel extends StreakUpdateResult {
  const StreakUpdateResultModel({
    required super.currentStreak,
    required super.longestStreak,
    required super.totalDaysActive,
    required super.freezeCount,
    required super.streakIncreased,
    required super.streakSaved,
  });

  /// Factory constructor from JSON
  factory StreakUpdateResultModel.fromJson(Map<String, dynamic> json) {
    return StreakUpdateResultModel(
      currentStreak: json['current_streak'] ?? 0,
      longestStreak: json['longest_streak'] ?? 0,
      totalDaysActive: json['total_days_active'] ?? 0,
      freezeCount: json['freeze_count'] ?? 0,
      streakIncreased: json['streak_increased'] ?? false,
      streakSaved: json['streak_saved'] ?? false,
    );
  }

  /// Convert to domain entity
  StreakUpdateResult toEntity() {
    return StreakUpdateResult(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalDaysActive: totalDaysActive,
      freezeCount: freezeCount,
      streakIncreased: streakIncreased,
      streakSaved: streakSaved,
    );
  }
}
