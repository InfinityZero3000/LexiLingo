import 'package:equatable/equatable.dart';

/// Streak Entity
/// Represents user's learning streak information
/// Clean Architecture: Domain layer entity
class StreakEntity extends Equatable {
  /// Current consecutive days of learning
  final int currentStreak;

  /// Best streak ever achieved
  final int longestStreak;

  /// Total days with learning activity
  final int totalDaysActive;

  /// Last date of learning activity (ISO format)
  final String? lastActivityDate;

  /// Available streak freezes
  final int freezeCount;

  /// Whether user has completed activity today
  final bool isActiveToday;

  /// Whether streak will be lost if no activity today
  final bool streakAtRisk;

  /// Activity flags for each day of the current week (Mon=0 … Sun=6)
  final List<bool> weeklyActivity;

  /// The previous streak value saved when the streak broke
  final int previousStreak;

  /// Number of streak restores used this month
  final int restoresUsedThisMonth;

  /// Remaining restores for this month
  final int restoresRemaining;

  /// Whether the streak can currently be restored
  final bool canRestore;

  /// Whether the daily streak reward is available to claim
  final bool isDailyRewardAvailable;

  const StreakEntity({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalDaysActive,
    this.lastActivityDate,
    required this.freezeCount,
    required this.isActiveToday,
    required this.streakAtRisk,
    List<bool>? weeklyActivity,
    this.previousStreak = 0,
    this.restoresUsedThisMonth = 0,
    this.restoresRemaining = 3,
    this.canRestore = false,
    this.isDailyRewardAvailable = false,
  }) : weeklyActivity =
           weeklyActivity ??
           const [false, false, false, false, false, false, false];

  /// Factory constructor for empty/default streak
  factory StreakEntity.empty() {
    return const StreakEntity(
      currentStreak: 0,
      longestStreak: 0,
      totalDaysActive: 0,
      lastActivityDate: null,
      freezeCount: 0,
      isActiveToday: false,
      streakAtRisk: false,
      weeklyActivity: [false, false, false, false, false, false, false],
      previousStreak: 0,
      restoresUsedThisMonth: 0,
      restoresRemaining: 3,
      canRestore: false,
      isDailyRewardAvailable: false,
    );
  }

  /// Check if user has any streak
  bool get hasStreak => currentStreak > 0;

  /// Check if this is a milestone streak (7, 14, 30, 60, 100, 365 days)
  bool get isMilestone {
    const milestones = [7, 14, 30, 60, 100, 365];
    return milestones.contains(currentStreak);
  }

  /// Get streak level for display
  String get streakLevel {
    if (currentStreak >= 365) return 'Legendary';
    if (currentStreak >= 100) return 'Master';
    if (currentStreak >= 60) return 'Expert';
    if (currentStreak >= 30) return 'Dedicated';
    if (currentStreak >= 14) return 'Committed';
    if (currentStreak >= 7) return 'Consistent';
    if (currentStreak >= 3) return 'Building';
    return 'Starting';
  }

  /// Get streak icon identifier based on current streak
  String get streakIcon {
    if (currentStreak >= 100) return 'trophy';
    if (currentStreak >= 30) return 'fire';
    if (currentStreak >= 7) return 'bolt';
    if (currentStreak >= 1) return 'star';
    return 'sparkles';
  }

  @override
  List<Object?> get props => [
    currentStreak,
    longestStreak,
    totalDaysActive,
    lastActivityDate,
    freezeCount,
    isActiveToday,
    streakAtRisk,
    weeklyActivity,
    previousStreak,
    restoresUsedThisMonth,
    restoresRemaining,
    canRestore,
    isDailyRewardAvailable,
  ];
}

/// Streak Update Response
/// Returned after updating streak from learning activity
class StreakUpdateResult extends Equatable {
  final int currentStreak;
  final int longestStreak;
  final int totalDaysActive;
  final int freezeCount;
  final bool streakIncreased;
  final bool streakSaved;
  final int previousStreak;
  final int restoresUsedThisMonth;
  final int restoresRemaining;
  final bool canRestore;
  final bool isDailyRewardAvailable;

  const StreakUpdateResult({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalDaysActive,
    required this.freezeCount,
    required this.streakIncreased,
    required this.streakSaved,
    this.previousStreak = 0,
    this.restoresUsedThisMonth = 0,
    this.restoresRemaining = 3,
    this.canRestore = false,
    this.isDailyRewardAvailable = false,
  });

  @override
  List<Object?> get props => [
    currentStreak,
    longestStreak,
    totalDaysActive,
    freezeCount,
    streakIncreased,
    streakSaved,
    previousStreak,
    restoresUsedThisMonth,
    restoresRemaining,
    canRestore,
    isDailyRewardAvailable,
  ];
}
