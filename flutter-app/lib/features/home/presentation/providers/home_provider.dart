import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/utils/freshness.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/user/domain/entities/user.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_weekly_progress_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// Home Provider
/// Manages home screen state including featured courses and user dashboard data
///
/// Following agent-skills/language-learning-patterns:
/// - progress-learning-streaks: Weekly progress visualization (3-5x engagement)
class HomeProvider with ChangeNotifier {
  final GetCoursesUseCase getCoursesUseCase;
  final GetEnrolledCoursesUseCase getEnrolledCoursesUseCase;
  final GetWeeklyProgressUseCase? getWeeklyProgressUseCase;
  final VocabularyRepository? vocabularyRepository;

  HomeProvider({
    required this.getCoursesUseCase,
    required this.getEnrolledCoursesUseCase,
    this.getWeeklyProgressUseCase,
    this.vocabularyRepository,
  });

  int _generation = 0;
  Future<void>? _weeklyLoad;
  final Freshness _weeklyFreshness = Freshness();

  // State: Featured Courses
  List<CourseEntity> _featuredCourses = [];
  bool _isLoadingCourses = false;
  String? _coursesError;

  // State: Enrolled Courses
  List<CourseEntity> _enrolledCourses = [];
  bool _isLoadingEnrolled = false;
  String? _enrolledError;

  // State: User Dashboard
  User? _currentUser;
  int? _goalTarget;
  bool _isLoadingDashboard = false;
  UiText? _dashboardError;

  // State: Weekly Progress (Task 1.3)
  WeeklyProgressEntity _weeklyProgress = WeeklyProgressEntity.empty();
  bool _isLoadingWeekly = false;

  // State: Word of the Day
  VocabularyItemEntity? _wordOfDay;
  bool _isLoadingWordOfDay = false;

  // Getters
  List<CourseEntity> get featuredCourses => _featuredCourses;
  List<CourseEntity> get enrolledCourses => _enrolledCourses;
  bool get isLoadingCourses => _isLoadingCourses;
  bool get isLoadingEnrolled => _isLoadingEnrolled;
  String? get coursesError => _coursesError;
  String? get enrolledError => _enrolledError;
  // Only show critical errors (courses/dashboard), not enrolled error which is secondary
  String? get errorMessage => _coursesError ?? _dashboardError?.resolve();

  User? get currentUser => _currentUser;
  String get userName =>
      _currentUser?.name ?? _currentUser?.email ?? 'profile.guestUser'.tr();
  int get totalXP => _currentUser?.totalXP ?? 0;
  int get streakDays => _weeklyProgress.currentStreak;

  /// Week progress as list of booleans for UI visualization
  /// Returns true for each day that had activity
  List<bool> get weekProgress =>
      _weeklyProgress.weekProgress.map((day) => day.hasActivity).toList();

  /// Get weekly progress entity for detailed display
  WeeklyProgressEntity get weeklyProgress => _weeklyProgress;
  bool get isLoadingWeekly => _isLoadingWeekly;

  VocabularyItemEntity? get wordOfDay => _wordOfDay;
  bool get isLoadingWordOfDay => _isLoadingWordOfDay;

  // Weekly progress is the server's record of today's XP, so changing the goal
  // must never change what was earned. The persisted target lives in
  // SettingsProvider; this only mirrors a change made from the home sheet.
  bool get hasDailyXP => _weeklyProgress.todayProgress != null;
  int get dailyXP => _weeklyProgress.todayProgress?.xpEarned ?? 0;
  int get dailyGoalXP => _goalTarget ?? 50;
  double get dailyProgressPercentage {
    final goal = dailyGoalXP;
    return goal > 0 ? (dailyXP / goal).clamp(0.0, 1.0) : 0.0;
  }

  bool get isLoadingDashboard => _isLoadingDashboard;
  String? get dashboardError => _dashboardError?.resolve();

  bool get isLoading =>
      _isLoadingCourses || _isLoadingDashboard || _isLoadingWeekly;

  /// Load weekly progress for home screen chart (Task 1.3)
  Future<void> loadWeeklyProgress({Duration? maxAge}) {
    if (getWeeklyProgressUseCase == null) return Future<void>.value();
    if (_weeklyFreshness.isFresh(maxAge)) return Future<void>.value();
    final inFlight = _weeklyLoad;
    if (inFlight != null) return inFlight;
    final run = _loadWeeklyProgress();
    _weeklyLoad = run;
    return run.whenComplete(() {
      if (identical(_weeklyLoad, run)) _weeklyLoad = null;
    });
  }

  Future<void> _loadWeeklyProgress() async {
    _isLoadingWeekly = true;
    notifyListeners();

    final generation = _generation;
    final result = await getWeeklyProgressUseCase!.call();
    if (generation != _generation) return;

    result.fold((failure) {}, (data) {
      _weeklyProgress = data;
      _weeklyFreshness.mark();
    });

    _isLoadingWeekly = false;
    notifyListeners();
  }

  Future<void> refreshWeeklyProgressSilently({Duration? maxAge}) async {
    if (getWeeklyProgressUseCase == null) return;
    if (_weeklyFreshness.isFresh(maxAge)) return;
    final inFlight = _weeklyLoad;
    if (inFlight != null) return inFlight;
    final generation = _generation;
    final result = await getWeeklyProgressUseCase!.call();
    if (generation != _generation) return;
    result.fold((_) {}, (data) {
      _weeklyProgress = data;
      _weeklyFreshness.mark();
      notifyListeners();
    });
  }

  /// Load featured courses for home screen
  Future<void> loadFeaturedCourses() async {
    _isLoadingCourses = true;
    _coursesError = null;
    notifyListeners();

    final generation = _generation;
    final result = await getCoursesUseCase(
      const GetCoursesParams(page: 1, pageSize: 6),
    );
    if (generation != _generation) return;

    result.fold(
      (failure) {
        _coursesError = failure.message;
      },
      (data) {
        final (courses, _) = data;
        _featuredCourses = courses;
        _coursesError = null;
      },
    );

    _isLoadingCourses = false;
    notifyListeners();
  }

  /// Load enrolled courses for "Continue Learning" section
  Future<void> loadEnrolledCourses() async {
    _isLoadingEnrolled = true;
    _enrolledError = null;
    notifyListeners();

    final generation = _generation;
    final result = await getEnrolledCoursesUseCase(page: 1, pageSize: 10);
    if (generation != _generation) return;

    result.fold(
      (failure) {
        _enrolledError = failure.message;
      },
      (data) {
        final (courses, _) = data;
        _enrolledCourses = courses;
        _enrolledError = null;
      },
    );

    _isLoadingEnrolled = false;
    notifyListeners();
  }

  /// Update current user data
  void setCurrentUser(User? user) {
    _currentUser = user;
    notifyListeners();
  }

  /// Mirror the target XP chosen by the learner.
  void updateDailyGoalTarget(int targetXP) {
    _goalTarget = targetXP;
    notifyListeners();
  }

  /// Load dashboard data (user stats, goals, etc.)
  Future<void> loadDashboard(User user) async {
    _dashboardError = null;
    _currentUser = user;
    notifyListeners();
  }

  /// Refresh all home screen data
  Future<void> refreshData() async {
    await Future.wait([
      loadFeaturedCourses(),
      loadEnrolledCourses(),
      loadWeeklyProgress(),
      loadWordOfDay(),
      if (_currentUser != null) loadDashboard(_currentUser!),
    ]);
  }

  Future<void> loadWordOfDay() async {
    if (vocabularyRepository == null) return;
    _isLoadingWordOfDay = true;
    notifyListeners();
    final generation = _generation;
    final result = await vocabularyRepository!.getWordOfDay();
    if (generation != _generation) return;
    result.fold((_) {}, (word) => _wordOfDay = word);
    _isLoadingWordOfDay = false;
    notifyListeners();
  }

  /// Load home data (combines courses and dashboard)
  Future<void> loadHomeData() async {
    await Future.wait([
      loadFeaturedCourses(),
      loadEnrolledCourses(),
      loadWeeklyProgress(maxAge: kPassiveReloadWindow),
      loadWordOfDay(),
    ]);
  }

  /// Clear all state
  void clear() {
    _generation++;
    _weeklyLoad = null;
    _weeklyFreshness.invalidate();
    _featuredCourses = [];
    _coursesError = null;
    _isLoadingCourses = false;

    _currentUser = null;
    _goalTarget = null;
    _dashboardError = null;
    _isLoadingDashboard = false;

    _weeklyProgress = WeeklyProgressEntity.empty();
    _isLoadingWeekly = false;

    _enrolledCourses = [];
    _enrolledError = null;
    _isLoadingEnrolled = false;
    _wordOfDay = null;
    _isLoadingWordOfDay = false;

    notifyListeners();
  }
}
