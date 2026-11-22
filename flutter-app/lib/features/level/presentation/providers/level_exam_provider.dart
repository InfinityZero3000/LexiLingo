import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';

/// One question of a level-exam sitting, with the level its section tests.
class LevelExamQuestion {
  final String id;
  final String level;
  final String prompt;
  final List<String> options;

  const LevelExamQuestion({
    required this.id,
    required this.level,
    required this.prompt,
    required this.options,
  });
}

/// Drives one sitting of the promotion exam. The server owns the paper, the
/// clock and the grading; this holds the answers and what to show.
class LevelExamProvider with ChangeNotifier {
  final ProficiencyDataSource _dataSource;

  LevelExamProvider({required ProficiencyDataSource dataSource})
    : _dataSource = dataSource;

  bool _loading = false;
  bool get loading => _loading;

  /// Why the exam cannot be sat now: not_ready, cooldown, no_questions,
  /// max_level, expired — or `error` when the request itself failed.
  String? _blockedReason;
  String? get blockedReason => _blockedReason;
  Map<String, dynamic> _gate = const {};
  Map<String, dynamic> get gate => _gate;

  String? _attemptId;
  String? get attemptId => _attemptId;
  DateTime? _expiresAt;
  DateTime? get expiresAt => _expiresAt;
  List<LevelExamQuestion> _questions = const [];
  List<LevelExamQuestion> get questions => _questions;
  final Map<String, String> _answers = {};
  Map<String, String> get answers => Map.unmodifiable(_answers);
  int _index = 0;
  int get index => _index;

  Map<String, dynamic>? _result;
  Map<String, dynamic>? get result => _result;

  bool get ready => _gate['available'] == true;
  bool get sitting => _attemptId != null && _result == null;
  LevelExamQuestion? get current =>
      _questions.isEmpty ? null : _questions[_index];
  bool get allAnswered => _questions.every((q) => _answers.containsKey(q.id));

  Future<void> loadEligibility() => _run(() async {
    _gate = await _dataSource.getLevelExamEligibility();
    _blockedReason = ready ? null : _gate['reason'] as String?;
  });

  Future<void> start() => _run(() async {
    final paper = await _dataSource.startLevelExam();
    _attemptId = paper['attempt_id'] as String?;
    _expiresAt = DateTime.tryParse('${paper['expires_at']}')?.toLocal();
    _questions = [
      for (final section in (paper['sections'] as List? ?? const []))
        for (final q in ((section as Map)['questions'] as List? ?? const []))
          LevelExamQuestion(
            id: '${(q as Map)['id']}',
            level: '${section['level']}',
            prompt: '${q['prompt']}',
            options: [
              for (final o in (q['options'] as List? ?? const [])) '$o',
            ],
          ),
    ];
    _answers
      ..clear()
      ..addAll({
        for (final e in ((paper['answers'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      });
    _index = 0;
    _result = null;
    if (_questions.isEmpty) {
      _attemptId = null;
      _blockedReason = 'no_questions';
    }
  });

  void answer(String option) {
    final question = current;
    if (question == null) return;
    _answers[question.id] = option;
    notifyListeners();
  }

  void goTo(int index) {
    if (index < 0 || index >= _questions.length) return;
    _index = index;
    notifyListeners();
  }

  /// Returns true when the learner's certified level moved.
  Future<bool> submit() async {
    final id = _attemptId;
    if (id == null || _loading) return false;
    await _run(() async {
      _result = await _dataSource.submitLevelExam(id, Map.of(_answers));
    });
    final refused =
        _result == null && _blockedReason != null && _blockedReason != 'error';
    if (refused) {
      _attemptId = null;
      notifyListeners();
    }
    return _result?['passed'] == true;
  }

  Future<void> _run(Future<void> Function() body) async {
    _loading = true;
    notifyListeners();
    try {
      await body();
    } on ApiErrorException catch (e) {
      final details = e.details ?? const <String, dynamic>{};
      _gate = {..._gate, ...details, 'available': false};
      _blockedReason = details['reason'] as String? ?? 'error';
    } catch (e) {
      debugPrint('Level exam request failed: $e');
      _blockedReason = 'error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
