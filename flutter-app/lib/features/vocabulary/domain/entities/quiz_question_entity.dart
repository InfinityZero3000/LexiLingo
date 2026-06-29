import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';

/// Direction a quiz question tests the word in.
/// - [termToMeaning]: show the English term, pick its meaning.
/// - [meaningToTerm]: show the meaning, pick the English term.
enum QuizDirection { termToMeaning, meaningToTerm }

/// One selectable answer in a multiple-choice quiz question.
class QuizOption {
  final String text;
  final bool isCorrect;

  const QuizOption({required this.text, required this.isCorrect});
}

/// A single Quizlet-style multiple-choice question generated from a due word.
/// Each question is tied back to its [card] so the result can feed FSRS.
class QuizQuestionEntity {
  final ReviewCardEntity card;
  final QuizDirection direction;
  final String prompt;
  final List<QuizOption> options;

  const QuizQuestionEntity({
    required this.card,
    required this.direction,
    required this.prompt,
    required this.options,
  });

  String get vocabularyId => card.userVocabulary.vocabularyId;

  int? get correctIndex {
    final i = options.indexWhere((o) => o.isCorrect);
    return i >= 0 ? i : null;
  }
}
