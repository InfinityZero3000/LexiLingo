import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';

/// Sends finished, graded activity to the CEFR skill scores.
///
/// Surfaces that grade an answer on the device — news and book quizzes,
/// pronunciation assessment — used to show the score and drop it. Nothing
/// outside lesson and game completion reached `UserSkillScore`, so reading,
/// listening, speaking and writing stayed at zero however much the learner
/// practised them.
///
/// Fire-and-forget by design: a learner has already seen their result by the
/// time this runs, and a failed background write must never surface as an
/// error on top of it. Mirrors [ChatMistakeRecorder]'s shape.
class SkillEventRecorder {
  const SkillEventRecorder({ProficiencyDataSource? dataSource})
    : _dataSource = dataSource;

  final ProficiencyDataSource? _dataSource;

  ProficiencyDataSource? get _resolved {
    if (_dataSource != null) return _dataSource;
    if (!sl.isRegistered<ProficiencyDataSource>()) return null;
    return sl<ProficiencyDataSource>();
  }

  Future<void> record(List<ExerciseResultData> results) async {
    if (results.isEmpty) return;
    final dataSource = _resolved;
    if (dataSource == null) return;

    try {
      await dataSource.recordExercises(results.map((r) => r.toJson()).toList());
    } catch (e) {
      debugPrint('SkillEventRecorder: failed to record ${results.length} result(s): $e');
    }
  }
}

/// CEFR level for content that carries its own grading, falling back to B1 —
/// the mid-point the news and book APIs already default to.
String normalizeCefrLevel(String? level) {
  const allowed = {'A1', 'A2', 'B1', 'B2', 'C1', 'C2'};
  final upper = (level ?? '').trim().toUpperCase();
  return allowed.contains(upper) ? upper : 'B1';
}

/// Concept id for a word, matching `_vocab_concept_id` in
/// backend-service/app/crud/vocabulary.py. The two are kept in sync by hand —
/// a mismatch silently creates a second concept for the same word instead of
/// failing, so change both together.
String? vocabConceptId(String word) {
  final parts = word.trim().toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (parts.isEmpty) return null;
  return 'vocab:${parts.join('_')}';
}
