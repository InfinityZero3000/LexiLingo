import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_course_detail_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_in_course_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_categories_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_by_category_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';

/// Course Provider
/// Manages course state and business logic for UI
class CourseProvider with ChangeNotifier {
  final GetCoursesUseCase getCoursesUseCase;
  final GetCourseDetailUseCase getCourseDetailUseCase;
  final EnrollInCourseUseCase enrollInCourseUseCase;
  final GetCategoriesUseCase getCategoriesUseCase;
  final GetCoursesByCategoryUseCase getCoursesByCategoryUseCase;
  final GetEnrolledCoursesUseCase getEnrolledCoursesUseCase;

  CourseProvider({
    required this.getCoursesUseCase,
    required this.getCourseDetailUseCase,
    required this.enrollInCourseUseCase,
    required this.getCategoriesUseCase,
    required this.getCoursesByCategoryUseCase,
    required this.getEnrolledCoursesUseCase,
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

  // State: Categories
  List<CourseCategoryEntity> _categories = [];
  bool _isLoadingCategories = false;
  String? _categoriesError;

  // State: Enrolled Courses
  List<CourseEntity> _enrolledCourses = [];
  bool _isLoadingEnrolled = false;
  String? _enrolledError;

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

  List<CourseCategoryEntity> get categories => _categories;
  bool get isLoadingCategories => _isLoadingCategories;
  String? get categoriesError => _categoriesError;

  List<CourseEntity> get enrolledCourses => _enrolledCourses;
  bool get isLoadingEnrolled => _isLoadingEnrolled;
  String? get enrolledError => _enrolledError;

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

  /// Group courses by category (level)
  /// Returns a map with category names as keys and list of courses as values
  Map<String, List<CourseEntity>> get coursesByCategory {
    final Map<String, List<CourseEntity>> grouped = {};
    
    // Define category order
    const categoryOrder = ['Beginner', 'Intermediate', 'Advanced'];
    
    // Initialize categories
    for (final category in categoryOrder) {
      grouped[category] = [];
    }
    
    // Group courses by level
    for (final course in _courses) {
      final category = course.level;
      if (grouped.containsKey(category)) {
        grouped[category]!.add(course);
      } else {
        // For any other levels, add to a separate category
        grouped[category] = [course];
      }
    }
    
    // Remove empty categories
    grouped.removeWhere((key, value) => value.isEmpty);
    
    return grouped;
  }

  /// Group courses by language
  Map<String, List<CourseEntity>> get coursesByLanguage {
    final Map<String, List<CourseEntity>> grouped = {};
    
    for (final course in _courses) {
      final language = course.language;
      if (grouped.containsKey(language)) {
        grouped[language]!.add(course);
      } else {
        grouped[language] = [course];
      }
    }
    
    return grouped;
  }

  /// Group courses by first tag (if available)
  Map<String, List<CourseEntity>> get coursesByTopic {
    final Map<String, List<CourseEntity>> grouped = {};
    
    for (final course in _courses) {
      // Use first tag as topic, or "General" if no tags
      final topic = course.tags.isNotEmpty ? course.tags.first : 'General';
      if (grouped.containsKey(topic)) {
        grouped[topic]!.add(course);
      } else {
        grouped[topic] = [course];
      }
    }
    
    return grouped;
  }

  /// Get all unique categories/levels from courses
  List<String> get availableCategories {
    return _courses.map((c) => c.level).toSet().toList();
  }

  /// Get all unique languages from courses  
  List<String> get availableLanguages {
    return _courses.map((c) => c.language).toSet().toList();
  }

  /// Get all unique topics (tags) from courses
  List<String> get availableTopics {
    final topics = <String>{};
    for (final course in _courses) {
      topics.addAll(course.tags);
    }
    return topics.toList();
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

  /// Load all categories
  Future<void> loadCategories({bool activeOnly = true}) async {
    if (_isLoadingCategories) return;

    _isLoadingCategories = true;
    _categoriesError = null;
    notifyListeners();

    final result = await getCategoriesUseCase(activeOnly: activeOnly);

    result.fold(
      (failure) {
        _categoriesError = _getErrorMessage(failure);
        _isLoadingCategories = false;
        notifyListeners();
      },
      (categories) {
        _categories = categories;
        _categoriesError = null;
        _isLoadingCategories = false;
        notifyListeners();
      },
    );
  }

  /// Load courses by specific category
  Future<void> loadCoursesByCategory(String categoryId, {int page = 1, bool append = false}) async {
    if (_isLoadingCourses) return;

    _isLoadingCourses = true;
    _coursesError = null;
    _currentPage = page;

    if (!append) {
      _courses = [];
    }

    notifyListeners();

    final result = await getCoursesByCategoryUseCase(
      categoryId: categoryId,
      page: page,
      pageSize: 20,
    );

    result.fold(
      (failure) {
        _coursesError = _getErrorMessage(failure);
        _isLoadingCourses = false;
        notifyListeners();
      },
      (data) {
        final (newCourses, totalPages) = data;
        if (append) {
          _courses.addAll(newCourses);
        } else {
          _courses = newCourses;
        }
        _totalPages = totalPages;
        _coursesError = null;
        _isLoadingCourses = false;
        notifyListeners();
      },
    );
  }

  /// Load enrolled courses
  Future<void> loadEnrolledCourses({
    int page = 1,
    bool append = false,
  }) async {
    if (_isLoadingEnrolled) return;

    _isLoadingEnrolled = true;
    _enrolledError = null;

    if (!append) {
      _enrolledCourses = [];
    }

    notifyListeners();

    final result = await getEnrolledCoursesUseCase(
      page: page,
      pageSize: 20,
    );

    result.fold(
      (failure) {
        _enrolledError = _getErrorMessage(failure);
        _isLoadingEnrolled = false;
        notifyListeners();
      },
      (data) {
        final (newCourses, totalPages) = data;
        if (append) {
          _enrolledCourses.addAll(newCourses);
        } else {
          _enrolledCourses = newCourses;
        }
        _enrolledError = null;
        _isLoadingEnrolled = false;
        notifyListeners();
      },
    );
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
