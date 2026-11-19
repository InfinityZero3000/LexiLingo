import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

import 'grammar_label.dart';

/// Saves a grammar correction surfaced in chat (topic_chat or lexi_chat) into
/// the Mistake Notebook, so corrections shown mid-conversation aren't lost
/// once the chat scrolls past them. Mirrors GameMistakeRecorder's pattern.
class ChatMistakeRecorder {
  final MistakeNotebookRepository _repository;
  final DateTime Function() _now;

  const ChatMistakeRecorder({
    MistakeNotebookRepository repository = const MistakeNotebookRepository(),
    DateTime Function()? now,
  }) : _repository = repository,
       _now = now ?? DateTime.now;

  /// True only when an entry was written; false when there was nothing to
  /// save (no corrected text), so callers must not claim "saved".
  ///
  /// [errorType] only decides the skill bucket (grammar or vocabulary); the
  /// error label itself is never stored as a skill.
  Future<bool> recordGrammarCorrection({
    required String sourceType,
    required String sourceId,
    required String original,
    required String corrected,
    required String explanation,
    String? errorType,
  }) async {
    if (corrected.trim().isEmpty) return false;

    await _repository.saveMistake(
      MistakeNotebookEntry(
        id: MistakeNotebookEntry.buildId(
          sourceType: sourceType,
          sourceId: sourceId,
          questionId: '$original->$corrected',
        ),
        sourceType: sourceType,
        sourceId: sourceId,
        sourceTitle: sourceType == 'topic_chat' ? 'Topic Chat' : 'Lexi Chat',
        question: original.trim().isNotEmpty ? original : corrected,
        selectedAnswer: original,
        correctAnswer: corrected,
        explanation: explanation,
        skill: grammarSkillFor(errorType),
        createdAt: _now(),
      ),
    );
    return true;
  }
}
