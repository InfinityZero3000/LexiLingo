import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_featured_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_course_usecase.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/core/services/streak_service.dart';

class HomeProvider with ChangeNotifier {
  final GetFeaturedCoursesUseCase getFeaturedCoursesUseCase;
  final GetEnrolledCoursesUseCase getEnrolledCoursesUseCase;
  final EnrollCourseUseCase enrollCourseUseCase;
  final UserProvider? userProvider;
  final StreakService streakService;

  HomeProvider({
    required this.getFeaturedCoursesUseCase,
    required this.getEnrolledCoursesUseCase,
    required this.enrollCourseUseCase,
    required this.streakService,
    this.userProvider,
  });

  List<Course> _featuredCourses = [];
  List<Course> _enrolledCourses = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Course> get featuredCourses => _featuredCourses;
  List<Course> get enrolledCourses => _enrolledCourses;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Real streak data from StreakService
  int _streakDays = 0;
  List<bool> _weekProgress = List.filled(7, false);

  int get streakDays => _streakDays;
  List<bool> get weekProgress => _weekProgress;

  // Get real daily progress from UserProvider
  int get dailyXP => userProvider?.todayGoal?.earnedXP ?? 0;
  int get dailyGoalXP => userProvider?.settings?.dailyGoalXP ?? 50;
  double get dailyProgressPercentage => dailyGoalXP > 0 ? (dailyXP / dailyGoalXP).clamp(0.0, 1.0) : 0.0;
  bool get isDailyGoalCompleted => dailyXP >= dailyGoalXP;

  // Get current user stats from UserProvider
  String get userName => userProvider?.user?.name ?? 'Learner';
  int get totalXP => userProvider?.user?.totalXP ?? 0;
  int get lessonsCompleted => userProvider?.user?.totalLessonsCompleted ?? 0;

  Future<void> loadHomeData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load courses and streak data in parallel
      final results = await Future.wait([
        getFeaturedCoursesUseCase(),
        getEnrolledCoursesUseCase(),
        _loadStreakData(),
      ]);

      _featuredCourses = results[0] as List<Course>;
      _enrolledCourses = results[1] as List<Course>;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load courses: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadStreakData() async {
    final userId = userProvider?.currentUserId;
    if (userId == null) {
      _streakDays = 0;
      _weekProgress = List.filled(7, false);
      return;
    }

    try {
      // Check if streak needs reset
      await streakService.checkAndResetStreakIfNeeded(userId);

      // Load current streak and week progress
      final results = await Future.wait([
        streakService.getCurrentStreak(userId),
        streakService.getWeekProgress(userId),
      ]);

      _streakDays = results[0] as int;
      _weekProgress = results[1] as List<bool>;
    } catch (e) {
      print('Failed to load streak data: $e');
      _streakDays = 0;
      _weekProgress = List.filled(7, false);
    }
  }

  Future<bool> enrollInCourse(int courseId) async {
    try {
      final success = await enrollCourseUseCase(courseId);
      if (success) {
        // Reload data to reflect the enrollment
        await loadHomeData();
      }
      return success;
    } catch (e) {
      _errorMessage = 'Failed to enroll in course: $e';
      notifyListeners();
      return false;
    }
  }

  /// Mark today as completed and update streak
  /// Called when user completes a lesson or reaches daily goal
  Future<void> markTodayCompleted() async {
    final userId = userProvider?.currentUserId;
    if (userId == null) return;

    try {
      await streakService.markTodayCompleted(userId);
      
      // Reload streak data to show updated values
      await _loadStreakData();
      notifyListeners();
    } catch (e) {
      print('Failed to mark today completed: $e');
    }
  }

  /// Refresh all data (pull-to-refresh)
  Future<void> refreshData() async {
    await loadHomeData();
    
    // Also refresh user data if provider available
    if (userProvider != null) {
      await userProvider!.loadUserData();
    }
  }

  void updateStreak(int days) {
    _streakDays = days;
    notifyListeners();
  }
}
