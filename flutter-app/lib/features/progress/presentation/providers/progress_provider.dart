import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_course_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_my_progress_usecase.dart';

/// Progress Provider
/// Manages progress tracking state
class ProgressProvider with ChangeNotifier {
  final GetMyProgressUseCase getMyProgressUseCase;
  final GetCourseProgressUseCase getCourseProgressUseCase;
  final CompleteLessonUseCase completeLessonUseCase;

  ProgressProvider({
    required this.getMyProgressUseCase,
    required this.getCourseProgressUseCase,
    required this.completeLessonUseCase,
  });

  // State
  bool _isLoading = false;
  String? _errorMessage;
  ProgressStatsEntity? _progressStats;
  CourseProgressWithUnits? _courseProgress;
  LessonCompletionResult? _lastCompletionResult;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProgressStatsEntity? get progressStats => _progressStats;
  CourseProgressWithUnits? get courseProgress => _courseProgress;
  LessonCompletionResult? get lastCompletionResult => _lastCompletionResult;

  UserProgressSummary? get summary => _progressStats?.summary;
  List<CourseProgressDetail> get courseProgressList =>
      _progressStats?.courseProgress ?? [];

  /// Fetch user's overall progress
  Future<void> fetchMyProgress() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await getMyProgressUseCase(NoParams());

    result.fold(
      (failure) {
        _isLoading = false;
        _errorMessage = failure.message;
        notifyListeners();
      },
      (progressStats) {
        _isLoading = false;
        _progressStats = progressStats;
        notifyListeners();
      },
    );
  }

  /// Fetch course progress with units
  Future<void> fetchCourseProgress(String courseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await getCourseProgressUseCase(courseId);

    result.fold(
      (failure) {
        _isLoading = false;
        _errorMessage = failure.message;
        notifyListeners();
      },
      (courseProgressWithUnits) {
        _isLoading = false;
        _courseProgress = courseProgressWithUnits;
        notifyListeners();
      },
    );
  }

  /// Complete a lesson with score
  Future<bool> submitLessonCompletion({
    required String lessonId,
    required double score,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await completeLessonUseCase(
      CompleteLessonParams(lessonId: lessonId, score: score),
    );

    bool success = false;

    result.fold(
      (failure) {
        _isLoading = false;
        _errorMessage = failure.message;
        notifyListeners();
      },
      (completionResult) {
        _isLoading = false;
        _lastCompletionResult = completionResult;
        success = true;
        notifyListeners();
      },
    );

    return success;
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear last completion result
  void clearLastCompletionResult() {
    _lastCompletionResult = null;
    notifyListeners();
  }

  /// Reset state
  void reset() {
    _isLoading = false;
    _errorMessage = null;
    _progressStats = null;
    _courseProgress = null;
    _lastCompletionResult = null;
    notifyListeners();
  }
}
