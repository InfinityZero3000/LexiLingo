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

  // Getters
  StreakEntity? get streak => _streak;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  StreakUpdateResult? get lastUpdateResult => _lastUpdateResult;
  
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
        // Update local streak with new values
        _streak = StreakEntity(
          currentStreak: updateResult.currentStreak,
          longestStreak: updateResult.longestStreak,
          totalDaysActive: updateResult.totalDaysActive,
          lastActivityDate: _streak?.lastActivityDate,
          freezeCount: updateResult.freezeCount,
          isActiveToday: true,
          streakAtRisk: false,
        );
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
          );
        }
        success = true;
      },
    );

    _isLoading = false;
    notifyListeners();
    return success;
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
    notifyListeners();
  }
}
