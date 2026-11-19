import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/core/utils/freshness.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_course_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_my_progress_usecase.dart';

/// Progress Provider
/// Manages progress tracking state
class ProgressProvider with ChangeNotifier {
  final GetMyProgressUseCase getMyProgressUseCase;
  final GetCourseProgressUseCase getCourseProgressUseCase;

  ProgressProvider({
    required this.getMyProgressUseCase,
    required this.getCourseProgressUseCase,
  });

  int _generation = 0;
  Future<void>? _myProgressLoad;
  final Freshness _myProgressFreshness = Freshness();

  // State
  bool _isLoading = false;
  String? _errorMessage;
  ProgressStatsEntity? _progressStats;
  CourseProgressWithUnits? _courseProgress;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProgressStatsEntity? get progressStats => _progressStats;
  CourseProgressWithUnits? get courseProgress => _courseProgress;

  UserProgressSummary? get summary => _progressStats?.summary;
  List<CourseProgressDetail> get courseProgressList =>
      _progressStats?.courseProgress ?? [];

  /// Fetch user's overall progress
  ///
  /// Concurrent calls share one request. [maxAge] lets passive callers skip a
  /// reload of data fetched that recently.
  Future<void> fetchMyProgress({Duration? maxAge}) {
    if (_myProgressFreshness.isFresh(maxAge)) return Future<void>.value();
    final inFlight = _myProgressLoad;
    if (inFlight != null) return inFlight;
    final run = _fetchMyProgress();
    _myProgressLoad = run;
    return run.whenComplete(() {
      if (identical(_myProgressLoad, run)) _myProgressLoad = null;
    });
  }

  Future<void> _fetchMyProgress() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final generation = _generation;
    final result = await getMyProgressUseCase(NoParams());
    if (generation != _generation) return;

    result.fold(
      (failure) {
        _isLoading = false;
        _errorMessage = failure.message;
        notifyListeners();
      },
      (progressStats) {
        _isLoading = false;
        _progressStats = progressStats;
        _myProgressFreshness.mark();
        notifyListeners();
      },
    );
  }

  /// The next passive [fetchMyProgress] refetches; call after learning activity.
  void invalidateFreshness() => _myProgressFreshness.invalidate();

  /// Fetch course progress with units
  Future<void> fetchCourseProgress(String courseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final generation = _generation;
    final result = await getCourseProgressUseCase(courseId);
    if (generation != _generation) return;

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

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset state
  void reset() {
    _generation++;
    _myProgressLoad = null;
    _myProgressFreshness.invalidate();
    _isLoading = false;
    _errorMessage = null;
    _progressStats = null;
    _courseProgress = null;
    notifyListeners();
  }
}
