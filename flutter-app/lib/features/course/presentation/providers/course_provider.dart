import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_course_detail_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_in_course_usecase.dart';

/// Course Provider
/// Manages course state and business logic for UI
class CourseProvider with ChangeNotifier {
  final GetCoursesUseCase getCoursesUseCase;
  final GetCourseDetailUseCase getCourseDetailUseCase;
  final EnrollInCourseUseCase enrollInCourseUseCase;

  CourseProvider({
    required this.getCoursesUseCase,
    required this.getCourseDetailUseCase,
    required this.enrollInCourseUseCase,
  });

  // State: Course List
  List<CourseEntity> _courses = [];
  bool _isLoadingCourses = false;
  String? _coursesError;
  int _currentPage = 1;
  int _totalPages = 1;
  String? _selectedLanguage;
  String? _selectedLevel;

  // State: Course Detail
  CourseDetailEntity? _courseDetail;
  bool _isLoadingDetail = false;
  String? _detailError;

  // State: Enrollment
  bool _isEnrolling = false;
  String? _enrollmentError;
  String? _enrollmentSuccess;

  // Getters
  List<CourseEntity> get courses => _courses;
  bool get isLoadingCourses => _isLoadingCourses;
  String? get coursesError => _coursesError;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get hasMorePages => _currentPage < _totalPages;
  String? get selectedLanguage => _selectedLanguage;
  String? get selectedLevel => _selectedLevel;

  CourseDetailEntity? get courseDetail => _courseDetail;
  bool get isLoadingDetail => _isLoadingDetail;
  String? get detailError => _detailError;

  bool get isEnrolling => _isEnrolling;
  String? get enrollmentError => _enrollmentError;
  String? get enrollmentSuccess => _enrollmentSuccess;

  /// Load courses with pagination and filters
  Future<void> loadCourses({
    int page = 1,
    String? language,
    String? level,
    bool append = false,
  }) async {
    if (_isLoadingCourses) return;

    _isLoadingCourses = true;
    _coursesError = null;
    _currentPage = page;
    _selectedLanguage = language;
    _selectedLevel = level;

    if (!append) {
      _courses = [];
    }

    notifyListeners();

    final params = GetCoursesParams(
      page: page,
      pageSize: 20,
      language: language,
      level: level,
    );

    final result = await getCoursesUseCase(params);

    result.fold(
      (failure) {
        _coursesError = _getErrorMessage(failure);
        _isLoadingCourses = false;
        notifyListeners();
      },
      (data) {
        final (coursesList, totalPages) = data;
        if (append) {
          _courses.addAll(coursesList);
        } else {
          _courses = coursesList;
        }
        _totalPages = totalPages;
        _isLoadingCourses = false;
        notifyListeners();
      },
    );
  }

  /// Load more courses (pagination)
  Future<void> loadMoreCourses() async {
    if (!hasMorePages || _isLoadingCourses) return;
    await loadCourses(
      page: _currentPage + 1,
      language: _selectedLanguage,
      level: _selectedLevel,
      append: true,
    );
  }

  /// Refresh courses (pull to refresh)
  Future<void> refreshCourses() async {
    await loadCourses(
      page: 1,
      language: _selectedLanguage,
      level: _selectedLevel,
    );
  }

  /// Filter courses by language
  Future<void> filterByLanguage(String? language) async {
    await loadCourses(
      page: 1,
      language: language,
      level: _selectedLevel,
    );
  }

  /// Filter courses by level
  Future<void> filterByLevel(String? level) async {
    await loadCourses(
      page: 1,
      language: _selectedLanguage,
      level: level,
    );
  }

  /// Clear all filters
  Future<void> clearFilters() async {
    await loadCourses(page: 1);
  }

  /// Load course detail with roadmap
  Future<void> loadCourseDetail(String courseId) async {
    _isLoadingDetail = true;
    _detailError = null;
    _courseDetail = null;
    notifyListeners();

    final result = await getCourseDetailUseCase(courseId);

    result.fold(
      (failure) {
        _detailError = _getErrorMessage(failure);
        _isLoadingDetail = false;
        notifyListeners();
      },
      (detail) {
        _courseDetail = detail;
        _isLoadingDetail = false;
        notifyListeners();
      },
    );
  }

  /// Enroll in a course
  Future<bool> enrollInCourse(String courseId) async {
    _isEnrolling = true;
    _enrollmentError = null;
    _enrollmentSuccess = null;
    notifyListeners();

    final result = await enrollInCourseUseCase(courseId);

    return result.fold(
      (failure) {
        _enrollmentError = _getErrorMessage(failure);
        _isEnrolling = false;
        notifyListeners();
        return false;
      },
      (message) {
        _enrollmentSuccess = message;
        _isEnrolling = false;
        
        // Update course detail enrollment status
        if (_courseDetail != null && _courseDetail!.id == courseId) {
          _courseDetail = CourseDetailEntity(
            id: _courseDetail!.id,
            title: _courseDetail!.title,
            description: _courseDetail!.description,
            language: _courseDetail!.language,
            level: _courseDetail!.level,
            tags: _courseDetail!.tags,
            thumbnailUrl: _courseDetail!.thumbnailUrl,
            totalXp: _courseDetail!.totalXp,
            estimatedDuration: _courseDetail!.estimatedDuration,
            totalLessons: _courseDetail!.totalLessons,
            isPublished: _courseDetail!.isPublished,
            createdAt: _courseDetail!.createdAt,
            updatedAt: _courseDetail!.updatedAt,
            isEnrolled: true,
            userProgress: _courseDetail!.userProgress ?? 0.0,
            units: _courseDetail!.units,
          );
        }
        
        // Update course in list
        final index = _courses.indexWhere((c) => c.id == courseId);
        if (index != -1) {
          _courses[index] = _courses[index].copyWith(isEnrolled: true);
        }
        
        notifyListeners();
        return true;
      },
    );
  }

  /// Clear enrollment messages
  void clearEnrollmentMessages() {
    _enrollmentError = null;
    _enrollmentSuccess = null;
    notifyListeners();
  }

  /// Get user-friendly error message
  String _getErrorMessage(dynamic failure) {
    return failure.toString().replaceAll('Failure: ', '');
  }

  /// Reset state
  void reset() {
    _courses = [];
    _courseDetail = null;
    _isLoadingCourses = false;
    _isLoadingDetail = false;
    _isEnrolling = false;
    _coursesError = null;
    _detailError = null;
    _enrollmentError = null;
    _enrollmentSuccess = null;
    _currentPage = 1;
    _totalPages = 1;
    _selectedLanguage = null;
    _selectedLevel = null;
    notifyListeners();
  }
}
