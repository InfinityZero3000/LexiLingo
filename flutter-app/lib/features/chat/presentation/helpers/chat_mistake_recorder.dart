import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

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

  Future<void> recordGrammarCorrection({
    required String sourceType,
    required String sourceId,
    required String original,
    required String corrected,
    required String explanation,
    String skill = 'grammar',
  }) async {
    if (corrected.trim().isEmpty) return;

    await _repository.saveMistake(
      MistakeNotebookEntry(
        id: MistakeNotebookEntry.buildId(
          sourceType: sourceType,
          sourceId: sourceId,
          questionId: '$original->$corrected',
          selectedAnswer: original,
        ),
        sourceType: sourceType,
        sourceId: sourceId,
        sourceTitle: sourceType == 'topic_chat' ? 'Topic Chat' : 'Lexi Chat',
        question: original.trim().isNotEmpty ? original : corrected,
        selectedAnswer: original,
        correctAnswer: corrected,
        explanation: explanation,
        skill: skill.trim().isEmpty ? 'grammar' : skill,
        createdAt: _now(),
      ),
    );
  }
}
