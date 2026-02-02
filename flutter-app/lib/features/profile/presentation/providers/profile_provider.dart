import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/usecases/get_recent_badges_usecase.dart';
import 'package:lexilingo_app/features/user/domain/entities/user_stats_entity.dart';
import 'package:lexilingo_app/features/user/domain/entities/weekly_activity_entity.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_stats_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_weekly_activity_usecase.dart';

/// Provider for Profile page data management
/// 
/// Following agent-skills/language-learning-patterns:
/// - gamification-achievement-badges: Display recent badges for 25-40% engagement boost
class ProfileProvider with ChangeNotifier {
  final GetUserStatsUseCase getUserStatsUseCase;
  final GetWeeklyActivityUseCase getWeeklyActivityUseCase;
  final GetRecentBadgesUseCase? getRecentBadgesUseCase;

  ProfileProvider({
    required this.getUserStatsUseCase,
    required this.getWeeklyActivityUseCase,
    this.getRecentBadgesUseCase,
  });

  // State
  UserStatsEntity? _stats;
  List<WeeklyActivityEntity> _weeklyActivity = [];
  List<UserAchievementEntity> _recentBadges = [];
  bool _isLoadingStats = false;
  bool _isLoadingActivity = false;
  bool _isLoadingBadges = false;
  String? _statsError;
  String? _activityError;
  String? _badgesError;

  // Getters
  UserStatsEntity? get stats => _stats;
  List<WeeklyActivityEntity> get weeklyActivity => _weeklyActivity;
  List<UserAchievementEntity> get recentBadges => _recentBadges;
  bool get isLoadingStats => _isLoadingStats;
  bool get isLoadingActivity => _isLoadingActivity;
  bool get isLoadingBadges => _isLoadingBadges;
  String? get statsError => _statsError;
  String? get activityError => _activityError;
  String? get badgesError => _badgesError;
  bool get hasStats => _stats != null;
  bool get hasBadges => _recentBadges.isNotEmpty;

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

  /// Load recent badges for profile display
  /// Following agent-skills/gamification-achievement-badges pattern
  Future<void> loadRecentBadges() async {
    if (getRecentBadgesUseCase == null) {
      _recentBadges = [];
      return;
    }

    _isLoadingBadges = true;
    _badgesError = null;
    notifyListeners();

    try {
      final badges = await getRecentBadgesUseCase!.call(limit: 4);
      _recentBadges = badges;
      _isLoadingBadges = false;
      notifyListeners();
    } catch (e) {
      _badgesError = e.toString();
      _isLoadingBadges = false;
      notifyListeners();
    }
  }

  /// Load all profile data
  Future<void> loadProfileData() async {
    await Future.wait([
      loadStats(),
      loadWeeklyActivity(),
      loadRecentBadges(),
    ]);
  }

  /// Refresh all data
  Future<void> refresh() async {
    _stats = null;
    _weeklyActivity = [];
    _recentBadges = [];
    _statsError = null;
    _activityError = null;
    _badgesError = null;
    await loadProfileData();
  }

  /// Clear all data
  void clear() {
    _stats = null;
    _weeklyActivity = [];
    _recentBadges = [];
    _isLoadingStats = false;
    _isLoadingActivity = false;
    _isLoadingBadges = false;
    _statsError = null;
    _activityError = null;
    _badgesError = null;
    notifyListeners();
  }
}
