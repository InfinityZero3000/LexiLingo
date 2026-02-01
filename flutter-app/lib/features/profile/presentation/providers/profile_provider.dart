import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/user/domain/entities/user_stats_entity.dart';
import 'package:lexilingo_app/features/user/domain/entities/weekly_activity_entity.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_stats_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_weekly_activity_usecase.dart';

/// Provider for Profile page data management
class ProfileProvider with ChangeNotifier {
  final GetUserStatsUseCase getUserStatsUseCase;
  final GetWeeklyActivityUseCase getWeeklyActivityUseCase;

  ProfileProvider({
    required this.getUserStatsUseCase,
    required this.getWeeklyActivityUseCase,
  });

  // State
  UserStatsEntity? _stats;
  List<WeeklyActivityEntity> _weeklyActivity = [];
  bool _isLoadingStats = false;
  bool _isLoadingActivity = false;
  String? _statsError;
  String? _activityError;

  // Getters
  UserStatsEntity? get stats => _stats;
  List<WeeklyActivityEntity> get weeklyActivity => _weeklyActivity;
  bool get isLoadingStats => _isLoadingStats;
  bool get isLoadingActivity => _isLoadingActivity;
  String? get statsError => _statsError;
  String? get activityError => _activityError;
  bool get hasStats => _stats != null;

  /// Load user statistics
  Future<void> loadStats() async {
    _isLoadingStats = true;
    _statsError = null;
    notifyListeners();

    final result = await getUserStatsUseCase();

    result.fold(
      (failure) {
        _statsError = failure.message;
        _isLoadingStats = false;
        notifyListeners();
      },
      (stats) {
        _stats = stats;
        _isLoadingStats = false;
        notifyListeners();
      },
    );
  }

  /// Load weekly activity data
  Future<void> loadWeeklyActivity() async {
    _isLoadingActivity = true;
    _activityError = null;
    notifyListeners();

    final result = await getWeeklyActivityUseCase();

    result.fold(
      (failure) {
        _activityError = failure.message;
        _isLoadingActivity = false;
        notifyListeners();
      },
      (activities) {
        _weeklyActivity = activities;
        _isLoadingActivity = false;
        notifyListeners();
      },
    );
  }

  /// Load all profile data
  Future<void> loadProfileData() async {
    await Future.wait([
      loadStats(),
      loadWeeklyActivity(),
    ]);
  }

  /// Refresh all data
  Future<void> refresh() async {
    _stats = null;
    _weeklyActivity = [];
    _statsError = null;
    _activityError = null;
    await loadProfileData();
  }

  /// Clear all data
  void clear() {
    _stats = null;
    _weeklyActivity = [];
    _isLoadingStats = false;
    _isLoadingActivity = false;
    _statsError = null;
    _activityError = null;
    notifyListeners();
  }
}
