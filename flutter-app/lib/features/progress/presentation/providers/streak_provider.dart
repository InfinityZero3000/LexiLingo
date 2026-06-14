import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Streak Provider
/// Manages streak state for gamification UI
/// Clean Architecture: Presentation layer state management
class StreakProvider extends ChangeNotifier {
  final ProgressRepository _repository;

  StreakProvider({required ProgressRepository repository})
    : _repository = repository;

  // State
  StreakEntity? _streak;
  bool _isLoading = false;
  String? _errorMessage;
  StreakUpdateResult? _lastUpdateResult;
  bool _milestoneJustReached = false;

  // Getters
  StreakEntity? get streak => _streak;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  StreakUpdateResult? get lastUpdateResult => _lastUpdateResult;
  bool get milestoneJustReached => _milestoneJustReached;

  /// Current streak count (0 if not loaded)
  int get currentStreak => _streak?.currentStreak ?? 0;

  /// Whether user has learned today
  bool get isActiveToday => _streak?.isActiveToday ?? false;

  /// Whether streak is at risk
  bool get streakAtRisk => _streak?.streakAtRisk ?? false;

  /// Available streak freezes
  int get freezeCount => _streak?.freezeCount ?? 0;

  /// Whether we have streak data
  bool get hasStreak => _streak != null;

  /// Load current user's streak
  Future<void> loadStreak() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getMyStreak();

    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _streak = StreakEntity.empty();
      },
      (streakData) {
        _streak = streakData;
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  /// Update streak after completing a learning activity
  /// Called after finishing a lesson or review session
  Future<bool> updateStreak() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.updateStreak();

    bool success = false;
    result.fold(
      (failure) {
        _errorMessage = failure.message;
      },
      (updateResult) {
        _lastUpdateResult = updateResult;
        // Update local streak with new values.
        // Mark today's slot in weeklyActivity as active (preserve existing days).
        final todayIndex = DateTime.now().weekday - 1; // 0=Mon … 6=Sun
        final updatedWeekly = List<bool>.from(
          _streak?.weeklyActivity ?? List.filled(7, false),
        );
        if (todayIndex >= 0 && todayIndex < 7) {
          updatedWeekly[todayIndex] = true;
        }
        _streak = StreakEntity(
          currentStreak: updateResult.currentStreak,
          longestStreak: updateResult.longestStreak,
          totalDaysActive: updateResult.totalDaysActive,
          lastActivityDate: _streak?.lastActivityDate,
          freezeCount: updateResult.freezeCount,
          isActiveToday: true,
          streakAtRisk: false,
          weeklyActivity: updatedWeekly,
          previousStreak: updateResult.previousStreak,
          restoresUsedThisMonth: updateResult.restoresUsedThisMonth,
          restoresRemaining: updateResult.restoresRemaining,
          canRestore: updateResult.canRestore,
          isDailyRewardAvailable: updateResult.isDailyRewardAvailable,
        );
        _milestoneJustReached =
            updateResult.streakIncreased && _streak!.isMilestone;
        success = true;
      },
    );

    _isLoading = false;
    notifyListeners();
    return success;
  }

  /// Use a streak freeze to protect current streak
  Future<bool> useFreeze() async {
    if (_streak == null || _streak!.freezeCount <= 0) {
      _errorMessage = 'No streak freezes available';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.useStreakFreeze();

    bool success = false;
    result.fold(
      (failure) {
        _errorMessage = failure.message;
      },
      (data) {
        // Update local streak
        if (_streak != null) {
          _streak = StreakEntity(
            currentStreak: data['current_streak'] ?? _streak!.currentStreak,
            longestStreak: _streak!.longestStreak,
            totalDaysActive: _streak!.totalDaysActive,
            lastActivityDate: _streak!.lastActivityDate,
            freezeCount: data['freeze_count'] ?? (_streak!.freezeCount - 1),
            isActiveToday: true,
            streakAtRisk: false,
            weeklyActivity: _streak!.weeklyActivity,
            previousStreak: _streak!.previousStreak,
            restoresUsedThisMonth: _streak!.restoresUsedThisMonth,
            restoresRemaining: _streak!.restoresRemaining,
            canRestore: _streak!.canRestore,
            isDailyRewardAvailable: _streak!.isDailyRewardAvailable,
          );
        }
        success = true;
      },
    );

    _isLoading = false;
    notifyListeners();
    return success;
  }

  /// Restore a broken streak
  Future<bool> restoreStreak() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.restoreStreak();

    bool success = false;
    result.fold(
      (failure) {
        _errorMessage = failure.message;
      },
      (streakData) {
        _streak = streakData;
        success = true;
      },
    );

    _isLoading = false;
    notifyListeners();
    return success;
  }

  /// Claim daily login reward
  Future<Map<String, dynamic>?> claimDailyReward() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.claimDailyReward();

    Map<String, dynamic>? successData;
    result.fold(
      (failure) {
        _errorMessage = failure.message;
      },
      (data) {
        successData = data;
        // Update local streak isDailyRewardAvailable flag
        if (_streak != null) {
          _streak = StreakEntity(
            currentStreak: _streak!.currentStreak,
            longestStreak: _streak!.longestStreak,
            totalDaysActive: _streak!.totalDaysActive,
            lastActivityDate: _streak!.lastActivityDate,
            freezeCount: _streak!.freezeCount,
            isActiveToday: _streak!.isActiveToday,
            streakAtRisk: _streak!.streakAtRisk,
            weeklyActivity: _streak!.weeklyActivity,
            previousStreak: _streak!.previousStreak,
            restoresUsedThisMonth: _streak!.restoresUsedThisMonth,
            restoresRemaining: _streak!.restoresRemaining,
            canRestore: _streak!.canRestore,
            isDailyRewardAvailable: false,
          );
        }
      },
    );

    _isLoading = false;
    notifyListeners();
    return successData;
  }

  /// Clear the milestone flag after the overlay has been shown.
  void clearMilestone() {
    _milestoneJustReached = false;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset state (for logout)
  void reset() {
    _streak = null;
    _isLoading = false;
    _errorMessage = null;
    _lastUpdateResult = null;
    _milestoneJustReached = false;
    notifyListeners();
  }
}
