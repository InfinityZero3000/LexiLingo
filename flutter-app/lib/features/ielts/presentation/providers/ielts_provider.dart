import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/datasources/ielts_data_source.dart';
import '../../domain/entities/ielts_entities.dart';

/// State for one IELTS sitting, plus the test catalogue.
///
/// Answers are held locally and pushed to the server on a timer rather than on
/// every keystroke: a Writing task would otherwise fire a request per character.
class IeltsProvider extends ChangeNotifier {
  final IeltsDataSource _dataSource;

  IeltsProvider({required IeltsDataSource dataSource})
    : _dataSource = dataSource;

  List<IeltsTestSummary> _tests = const [];
  List<Map<String, dynamic>> _history = const [];
  IeltsAttemptState? _attempt;
  IeltsResult? _result;
  final Map<String, dynamic> _answers = {};

  bool _loading = false;
  bool _submitting = false;
  String? _error;
  DateTime? _startedAt;
  Timer? _autosaveTimer;
  bool _dirty = false;

  List<IeltsTestSummary> get tests => _tests;
  List<Map<String, dynamic>> get history => _history;
  IeltsAttemptState? get attempt => _attempt;
  IeltsResult? get result => _result;
  Map<String, dynamic> get answers => Map.unmodifiable(_answers);
  bool get isLoading => _loading;
  bool get isSubmitting => _submitting;
  String? get error => _error;

  int get elapsedSeconds => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inSeconds;

  IeltsPaper get paper => _attempt?.paper ?? const IeltsPaper();

  int get answeredCount =>
      _answers.values.where((v) => v != null && v.toString().trim().isNotEmpty).length;

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  Future<void> loadTests({String? testType}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _tests = await _dataSource.listTests(testType: testType);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    try {
      _history = await _dataSource.listAttempts();
      notifyListeners();
    } catch (_) {
      // History is decoration on the list screen; failing it must not block.
    }
  }

  Future<bool> startTest(String testId, {String skillScope = 'full'}) async {
    _loading = true;
    _error = null;
    _result = null;
    notifyListeners();
    try {
      final state = await _dataSource.startAttempt(testId, skillScope: skillScope);
      _attempt = state;
      _answers
        ..clear()
        ..addAll(state.answers);
      _startedAt = DateTime.now();
      _beginAutosave();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setAnswer(String key, dynamic value) {
    _answers[key] = value;
    _dirty = true;
    notifyListeners();
  }

  String? answerFor(String key) => _answers[key]?.toString();

  void _beginAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final attemptId = _attempt?.attemptId;
    if (attemptId == null || !_dirty) return;
    _dirty = false;
    try {
      await _dataSource.saveAnswers(
        attemptId,
        Map<String, dynamic>.from(_answers),
        timeSpentSeconds: elapsedSeconds,
      );
    } catch (_) {
      // Keep the answers dirty so the next tick retries them.
      _dirty = true;
    }
  }

  Future<IeltsResult?> submit() async {
    final attemptId = _attempt?.attemptId;
    if (attemptId == null) return null;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      _autosaveTimer?.cancel();
      await _dataSource.submit(
        attemptId,
        Map<String, dynamic>.from(_answers),
        timeSpentSeconds: elapsedSeconds,
      );
      final result = await _dataSource.getResult(attemptId);
      _result = result;
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Re-read the result. Writing and Speaking are graded in the background, so
  /// the first result usually shows those as pending.
  Future<void> refreshResult() async {
    final attemptId = _attempt?.attemptId ?? _result?.attemptId;
    if (attemptId == null) return;
    try {
      _result = await _dataSource.getResult(attemptId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> openResult(String attemptId) async {
    _loading = true;
    notifyListeners();
    try {
      _result = await _dataSource.getResult(attemptId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
