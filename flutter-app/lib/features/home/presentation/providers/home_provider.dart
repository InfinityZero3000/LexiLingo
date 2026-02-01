import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/user/domain/entities/user.dart';
import 'package:lexilingo_app/features/user/domain/entities/daily_goal.dart';

/// Home Provider
/// Manages home screen state including featured courses and user dashboard data
class HomeProvider with ChangeNotifier {
  final GetCoursesUseCase getCoursesUseCase;
  final GetEnrolledCoursesUseCase getEnrolledCoursesUseCase;

  HomeProvider({
    required this.getCoursesUseCase,
    required this.getEnrolledCoursesUseCase,
  });

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
  DailyGoal? _todayGoal;
  bool _isLoadingDashboard = false;
  String? _dashboardError;

  // Getters
  List<CourseEntity> get featuredCourses => _featuredCourses;
  List<CourseEntity> get enrolledCourses => _enrolledCourses;
  bool get isLoadingCourses => _isLoadingCourses;
  bool get isLoadingEnrolled => _isLoadingEnrolled;
  String? get coursesError => _coursesError;
  String? get enrolledError => _enrolledError;
  String? get errorMessage => _coursesError ?? _dashboardError ?? _enrolledError;
  
  User? get currentUser => _currentUser;
  String get userName => _currentUser?.name ?? _currentUser?.email ?? 'User';
  int get totalXP => _currentUser?.totalXP ?? 0;
  int get streakDays => 0; // TODO: Calculate from DailyGoal records
  List<bool> get weekProgress => List.filled(7, false); // TODO: Load from backend
  
  DailyGoal? get todayGoal => _todayGoal;
  int get dailyXP => _todayGoal?.earnedXP ?? 0;
  int get dailyGoalXP => _todayGoal?.targetXP ?? 50;
  double get dailyProgressPercentage => _todayGoal?.progressPercentage ?? 0.0;
  
  bool get isLoadingDashboard => _isLoadingDashboard;
  String? get dashboardError => _dashboardError;
  
  bool get isLoading => _isLoadingCourses || _isLoadingDashboard;

  /// Load featured courses for home screen
  Future<void> loadFeaturedCourses() async {
    _isLoadingCourses = true;
    _coursesError = null;
    notifyListeners();

    final result = await getCoursesUseCase(
      const GetCoursesParams(page: 1, pageSize: 6),
    );

    result.fold(
      (failure) {
        _coursesError = failure.message;
        _featuredCourses = [];
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

    final result = await getEnrolledCoursesUseCase(
      page: 1,
      pageSize: 10,
    );

    result.fold(
      (failure) {
        _enrolledError = failure.message;
        _enrolledCourses = [];
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

  /// Update today's goal
  void setTodayGoal(DailyGoal? goal) {
    _todayGoal = goal;
    notifyListeners();
  }

  /// Load dashboard data (user stats, goals, etc.)
  Future<void> loadDashboard(User user) async {
    _isLoadingDashboard = true;
    _dashboardError = null;
    notifyListeners();

    try {
      // Set current user
      _currentUser = user;
      
      // Load today's goal (mock data for now)
      _todayGoal = DailyGoal(
        id: 1,  // Mock ID
        userId: user.id,
        date: DateTime.now(),
        targetXP: 50,
        earnedXP: 20,
      );

      _dashboardError = null;
    } catch (e) {
      _dashboardError = 'Failed to load dashboard: ${e.toString()}';
    } finally {
      _isLoadingDashboard = false;
      notifyListeners();
    }
  }

  /// Refresh all home screen data
  Future<void> refreshData() async {
    await Future.wait([
      loadFeaturedCourses(),
      loadEnrolledCourses(),
      if (_currentUser != null) loadDashboard(_currentUser!),
    ]);
  }

  /// Load home data (combines courses and dashboard)
  Future<void> loadHomeData() async {
    await Future.wait([
      loadFeaturedCourses(),
      loadEnrolledCourses(),
    ]);
  }

  /// Clear all state
  void clear() {
    _featuredCourses = [];
    _coursesError = null;
    _isLoadingCourses = false;
    
    _currentUser = null;
    _todayGoal = null;
    _dashboardError = null;
    _isLoadingDashboard = false;
    
    notifyListeners();
  }
}
