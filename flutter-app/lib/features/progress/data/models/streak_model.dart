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
    super.weeklyActivity,
    super.previousStreak,
    super.restoresUsedThisMonth,
    super.restoresRemaining,
    super.canRestore,
    super.isDailyRewardAvailable,
  });

  /// Factory constructor from JSON (API response)
  factory StreakModel.fromJson(Map<String, dynamic> json) {
    int readInt(List<String> keys, {int defaultValue = 0}) {
      for (final key in keys) {
        final value = json[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
      return defaultValue;
    }

    bool readBool(List<String> keys, {bool defaultValue = false}) {
      for (final key in keys) {
        final value = json[key];
        if (value is bool) return value;
        if (value is String) {
          if (value.toLowerCase() == 'true') return true;
          if (value.toLowerCase() == 'false') return false;
        }
      }
      return defaultValue;
    }

    final currentStreak = readInt([
      'current_streak',
      'currentStreak',
      'streak_days',
      'streakDays',
    ]);

    var longestStreak = readInt([
      'longest_streak',
      'longestStreak',
      'best_streak',
      'bestStreak',
    ]);

    var totalDaysActive = readInt([
      'total_days_active',
      'totalDaysActive',
      'total_days',
      'totalDays',
      'days_active',
      'daysActive',
    ]);

    var freezeCount = readInt([
      'freeze_count',
      'freezeCount',
      'freezes',
      'streak_freezes',
      'streakFreezes',
      'available_freezes',
      'availableFreezes',
    ]);

    // Defensive normalization for inconsistent backend payloads.
    if (longestStreak < currentStreak) longestStreak = currentStreak;
    if (totalDaysActive < currentStreak) totalDaysActive = currentStreak;
    if (freezeCount < 0) freezeCount = 0;

    List<bool> weeklyActivity = List.filled(7, false);
    final rawWeekly = json['weekly_activity'] ?? json['weeklyActivity'];
    if (rawWeekly is List) {
      weeklyActivity = List.generate(
        7,
        (i) => i < rawWeekly.length ? (rawWeekly[i] as bool? ?? false) : false,
      );
    }

    final previousStreak = readInt(['previous_streak', 'previousStreak']);
    final restoresUsedThisMonth = readInt(['restores_used_this_month', 'restoresUsedThisMonth']);
    final restoresRemaining = readInt(['restores_remaining', 'restoresRemaining'], defaultValue: 3);
    final canRestore = readBool(['can_restore', 'canRestore']);
    final isDailyRewardAvailable = readBool(['is_daily_reward_available', 'isDailyRewardAvailable']);

    return StreakModel(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalDaysActive: totalDaysActive,
      lastActivityDate: json['last_activity_date'],
      freezeCount: freezeCount,
      isActiveToday: readBool([
        'is_active_today',
        'isActiveToday',
        'active_today',
      ]),
      streakAtRisk: readBool(['streak_at_risk', 'streakAtRisk']),
      weeklyActivity: weeklyActivity,
      previousStreak: previousStreak,
      restoresUsedThisMonth: restoresUsedThisMonth,
      restoresRemaining: restoresRemaining,
      canRestore: canRestore,
      isDailyRewardAvailable: isDailyRewardAvailable,
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
      'weekly_activity': weeklyActivity,
      'previous_streak': previousStreak,
      'restores_used_this_month': restoresUsedThisMonth,
      'restores_remaining': restoresRemaining,
      'can_restore': canRestore,
      'is_daily_reward_available': isDailyRewardAvailable,
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
      weeklyActivity: weeklyActivity,
      previousStreak: previousStreak,
      restoresUsedThisMonth: restoresUsedThisMonth,
      restoresRemaining: restoresRemaining,
      canRestore: canRestore,
      isDailyRewardAvailable: isDailyRewardAvailable,
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
    super.previousStreak,
    super.restoresUsedThisMonth,
    super.restoresRemaining,
    super.canRestore,
    super.isDailyRewardAvailable,
  });

  /// Factory constructor from JSON
  factory StreakUpdateResultModel.fromJson(Map<String, dynamic> json) {
    int readInt(List<String> keys, {int defaultValue = 0}) {
      for (final key in keys) {
        final value = json[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
      return defaultValue;
    }

    bool readBool(List<String> keys, {bool defaultValue = false}) {
      for (final key in keys) {
        final value = json[key];
        if (value is bool) return value;
        if (value is String) {
          if (value.toLowerCase() == 'true') return true;
          if (value.toLowerCase() == 'false') return false;
        }
      }
      return defaultValue;
    }

    final currentStreak = readInt([
      'current_streak',
      'currentStreak',
      'streak_days',
      'streakDays',
    ]);
    var longestStreak = readInt([
      'longest_streak',
      'longestStreak',
      'best_streak',
      'bestStreak',
    ]);
    var totalDaysActive = readInt([
      'total_days_active',
      'totalDaysActive',
      'total_days',
      'totalDays',
    ]);

    if (longestStreak < currentStreak) longestStreak = currentStreak;
    if (totalDaysActive < currentStreak) totalDaysActive = currentStreak;

    final previousStreak = readInt(['previous_streak', 'previousStreak']);
    final restoresUsedThisMonth = readInt(['restores_used_this_month', 'restoresUsedThisMonth']);
    final restoresRemaining = readInt(['restores_remaining', 'restoresRemaining'], defaultValue: 3);
    final canRestore = readBool(['can_restore', 'canRestore']);
    final isDailyRewardAvailable = readBool(['is_daily_reward_available', 'isDailyRewardAvailable']);

    return StreakUpdateResultModel(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalDaysActive: totalDaysActive,
      freezeCount: readInt([
        'freeze_count',
        'freezeCount',
        'freezes',
        'streak_freezes',
        'streakFreezes',
      ]),
      streakIncreased: readBool(['streak_increased', 'streakIncreased']),
      streakSaved: readBool(['streak_saved', 'streakSaved']),
      previousStreak: previousStreak,
      restoresUsedThisMonth: restoresUsedThisMonth,
      restoresRemaining: restoresRemaining,
      canRestore: canRestore,
      isDailyRewardAvailable: isDailyRewardAvailable,
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
      previousStreak: previousStreak,
      restoresUsedThisMonth: restoresUsedThisMonth,
      restoresRemaining: restoresRemaining,
      canRestore: canRestore,
      isDailyRewardAvailable: isDailyRewardAvailable,
    );
  }
}
