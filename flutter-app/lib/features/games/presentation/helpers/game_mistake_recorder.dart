import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

class GameMistakeRecorder {
  final MistakeNotebookRepository _repository;
  final DateTime Function() _now;

  const GameMistakeRecorder({
    MistakeNotebookRepository repository = const MistakeNotebookRepository(),
    DateTime Function()? now,
  }) : _repository = repository,
       _now = now ?? DateTime.now;

  Future<void> recordFillBlankMiss({
    required FillBlankQuestion question,
    required String sessionId,
    required int questionIndex,
    required String selectedAnswer,
  }) async {
    if (_isCorrect(selectedAnswer, question.correctAnswer)) return;

    await _repository.saveMistake(
      _entry(
        sourceType: 'game_fill_blank',
        sourceId: _sourceId(sessionId, question.id, questionIndex),
        questionId: _questionId(question.id, question.sentence, questionIndex),
        sourceTitle: 'Fill in the Blank',
        question: question.sentence,
        selectedAnswer: selectedAnswer,
        correctAnswer: question.correctAnswer,
        explanation: question.explanation.isNotEmpty
            ? question.explanation
            : question.grammarTip,
        skill: 'grammar',
      ),
    );
  }

  Future<void> recordGrammarQuizMiss({
    required GrammarQuizQuestion question,
    required String sessionId,
    required int questionIndex,
    required String selectedAnswer,
  }) async {
    if (_isCorrect(selectedAnswer, question.correctAnswer)) return;

    await _repository.saveMistake(
      _entry(
        sourceType: 'game_grammar_quiz',
        sourceId: _sourceId(sessionId, question.id, questionIndex),
        questionId: _questionId(question.id, question.question, questionIndex),
        sourceTitle: question.topic.isEmpty
            ? 'Grammar Quiz'
            : 'Grammar Quiz - ${_formatTopic(question.topic)}',
        question: question.question,
        selectedAnswer: selectedAnswer,
        correctAnswer: question.correctAnswer,
        explanation: question.explanation,
        skill: question.topic.isEmpty ? 'grammar' : question.topic,
      ),
    );
  }

  MistakeNotebookEntry _entry({
    required String sourceType,
    required String sourceId,
    required String questionId,
    required String sourceTitle,
    required String question,
    required String selectedAnswer,
    required String correctAnswer,
    required String explanation,
    required String skill,
  }) {
    return MistakeNotebookEntry(
      id: MistakeNotebookEntry.buildId(
        sourceType: sourceType,
        sourceId: sourceId,
        questionId: questionId,
        selectedAnswer: selectedAnswer,
      ),
      sourceType: sourceType,
      sourceId: sourceId,
      sourceTitle: sourceTitle,
      question: question,
      selectedAnswer: selectedAnswer,
      correctAnswer: correctAnswer,
      explanation: explanation,
      skill: skill,
      createdAt: _now(),
    );
  }

  bool _isCorrect(String selectedAnswer, String correctAnswer) {
    return selectedAnswer.trim().toLowerCase() ==
        correctAnswer.trim().toLowerCase();
  }

  String _sourceId(String sessionId, String questionId, int questionIndex) {
    if (sessionId.isNotEmpty) return sessionId;
    if (questionId.isNotEmpty) return questionId;
    return 'question_$questionIndex';
  }

  String _questionId(String id, String question, int questionIndex) {
    if (id.isNotEmpty) return id;
    return '$questionIndex:$question';
  }

  String _formatTopic(String topic) {
    return topic
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
