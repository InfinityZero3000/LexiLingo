import 'package:flutter/foundation.dart';
import '../../domain/entities/user.dart';
import '../../domain/entities/settings.dart';
import '../../domain/entities/daily_goal.dart';
import '../../domain/usecases/get_user_usecase.dart';
import '../../domain/usecases/update_user_usecase.dart';
import '../../domain/usecases/get_settings_usecase.dart';
import '../../domain/usecases/update_settings_usecase.dart';
// import '../../domain/usecases/get_today_goal_usecase.dart'; // TODO: Create this file
import '../../domain/usecases/update_daily_progress_usecase.dart';
import '../../domain/usecases/get_current_streak_usecase.dart';

class UserProvider with ChangeNotifier {
  final GetUserUseCase getUserUseCase;
  final UpdateUserUseCase updateUserUseCase;
  final GetSettingsUseCase getSettingsUseCase;
  final UpdateSettingsUseCase updateSettingsUseCase;
  // final GetTodayGoalUseCase getTodayGoalUseCase; // TODO: Add after creating usecase
  final UpdateDailyProgressUseCase updateDailyProgressUseCase;
  final GetCurrentStreakUseCase getCurrentStreakUseCase;

  UserProvider({
    required this.getUserUseCase,
    required this.updateUserUseCase,
    required this.getSettingsUseCase,
    required this.updateSettingsUseCase,
    // required this.getTodayGoalUseCase, // TODO: Add after creating usecase
    required this.updateDailyProgressUseCase,
    required this.getCurrentStreakUseCase,
  });

  // Current user ID (from Firebase Auth)
  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  // User data
  User? _user;
  User? get user => _user;

  // Settings
  Settings? _settings;
  Settings? get settings => _settings;

  // Daily goal
  DailyGoal? _todayGoal;
  DailyGoal? get todayGoal => _todayGoal;

  // Current streak
  int _currentStreak = 0;
  int get currentStreak => _currentStreak;

  // Loading states
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Set current user
  void setCurrentUser(String userId) {
    _currentUserId = userId;
    loadUserData();
  }

  // Load all user data
  Future<void> loadUserData() async {
    if (_currentUserId == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load user profile, settings, and today's goal in parallel
      final results = await Future.wait([
        getUserUseCase(_currentUserId!),
        getSettingsUseCase(_currentUserId!),
        // getTodayGoalUseCase(_currentUserId!), // TODO: Add after creating usecase
        getCurrentStreakUseCase(_currentUserId!),
      ]);

      _user = results[0] as User?;
      _settings = results[1] as Settings?;
      // _todayGoal = results[2] as DailyGoal?; // TODO: Uncomment after usecase is created
      _todayGoal = null; // Temporary: Set to null until usecase is ready
      _currentStreak = results[2] as int; // Changed index from 3 to 2

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update user profile
  Future<void> updateUserProfile({
    String? name,
    String? email,
    String? avatarUrl,
  }) async {
    if (_user == null) return;

    try {
      final updatedUser = _user!.copyWith(
        name: name ?? _user!.name,
        email: email ?? _user!.email,
        avatarUrl: avatarUrl ?? _user!.avatarUrl,
      );

      await updateUserUseCase(updatedUser);
      _user = updatedUser;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Update settings
  Future<void> updateUserSettings(Settings newSettings) async {
    try {
      await updateSettingsUseCase(newSettings);
      _settings = newSettings;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Toggle notification
  Future<void> toggleNotification(bool enabled) async {
    if (_settings == null) return;

    final updated = _settings!.copyWith(notificationEnabled: enabled);
    await updateUserSettings(updated);
  }

  // Update daily goal XP
  Future<void> updateDailyGoalXP(int xp) async {
    if (_settings == null) return;

    final updated = _settings!.copyWith(dailyGoalXP: xp);
    await updateUserSettings(updated);
  }

  // Update theme
  Future<void> updateTheme(String theme) async {
    if (_settings == null) return;

    final updated = _settings!.copyWith(theme: theme);
    await updateUserSettings(updated);
  }

  // Record learning progress (called when user completes lesson)
  Future<void> recordProgress({
    required int xpEarned,
    int lessonsCompleted = 0,
    int wordsLearned = 0,
    int minutesSpent = 0,
  }) async {
    if (_currentUserId == null) return;

    try {
      await updateDailyProgressUseCase(
        userId: _currentUserId!,
        xpEarned: xpEarned,
        lessonsCompleted: lessonsCompleted,
        wordsLearned: wordsLearned,
        minutesSpent: minutesSpent,
      );

      // Reload user data to reflect changes
      await loadUserData();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
