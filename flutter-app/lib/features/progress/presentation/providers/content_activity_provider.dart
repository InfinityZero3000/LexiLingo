import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/progress/domain/entities/content_activity_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Credited activity on the library, podcast, video and news surfaces.
///
/// Read from the server's immutable XP transaction rows, so what this shows is
/// exactly what the system counted — which is the point of surfacing it: a
/// learner can see that time spent on content registered, and a source sitting
/// at zero is evidence nothing was recorded rather than a gap in the report.
class ContentActivityProvider extends ChangeNotifier {
  ContentActivityProvider({required ProgressRepository repository})
    : _repository = repository;

  final ProgressRepository _repository;

  ContentActivityEntity _activity = ContentActivityEntity.empty;
  bool _isLoading = false;
  String? _errorMessage;
  int _days = 7;

  ContentActivityEntity get activity => _activity;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get days => _days;

  /// Sources that report time, in the order they should be shown.
  List<ContentSourceActivityEntity> get timedSources =>
      _activity.bySource.where((s) => s.tracksMinutes).toList(growable: false);

  /// Sources credited per activity instead of by time (news, books).
  List<ContentSourceActivityEntity> get countedSources =>
      _activity.bySource.where((s) => !s.tracksMinutes).toList(growable: false);

  Future<void> load({int days = 7, bool force = false}) async {
    if (_isLoading) return;
    if (!force && days == _days && !_activity.isEmpty) return;

    _days = days;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getContentActivity(days: days);
    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _isLoading = false;
        notifyListeners();
      },
      (activity) {
        _activity = activity;
        _isLoading = false;
        notifyListeners();
      },
    );
  }
}
