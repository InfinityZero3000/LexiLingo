import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/quiz_question_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_due_vocabulary_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/submit_review_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// Tracks how a single word performed across its (up to two) quiz questions
/// so one aggregated FSRS review can be submitted per word.
class _WordProgress {
  final ReviewCardEntity card;
  final int questionCount;
  int answered = 0;
  int correct = 0;
  int timeSpentMs = 0;
  bool submitted = false;

  _WordProgress({required this.card, required this.questionCount});
}

/// Quiz Provider (Presentation Layer)
/// Drives the Quizlet-style multiple-choice review over FSRS-due words.
/// Generation is client-side; grading is mapped back to [ReviewQuality] and
/// submitted through the existing review endpoint so activity is logged and
/// the word is rescheduled by the backend FSRS scheduler.
class QuizProvider extends ChangeNotifier {
  static const int _defaultWordTarget = 10;
  static const int _optionsPerQuestion = 4;
  static const int _distractorPoolSize = 40;

  final GetDueVocabularyUseCase getDueVocabularyUseCase;
  final SubmitReviewUseCase submitReviewUseCase;
  final VocabularyRepository vocabularyRepository;

  QuizProvider({
    required this.getDueVocabularyUseCase,
    required this.submitReviewUseCase,
    required this.vocabularyRepository,
  });

  final Random _random = Random();

  bool _isLoading = false;
  String? _errorMessage;

  List<QuizQuestionEntity> _questions = [];
  int _currentIndex = 0;
  int? _selectedIndex;

  final Map<String, _WordProgress> _wordProgress = {};
  final List<Future<void>> _pendingSubmits = [];
  DateTime? _questionStartTime;
  DateTime? _startedAt;

  int _wordCount = 0;
  int _totalXpEarned = 0;

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasSession => _questions.isNotEmpty;
  int get totalQuestions => _questions.length;
  int get currentQuestionNumber => _currentIndex + 1;
  int get totalXpEarned => _totalXpEarned;

  QuizQuestionEntity? get currentQuestion =>
      _currentIndex < _questions.length ? _questions[_currentIndex] : null;

  int? get selectedIndex => _selectedIndex;
  bool get isAnswered => _selectedIndex != null;
  bool get isComplete => hasSession && _currentIndex >= _questions.length;

  double get progress =>
      _questions.isEmpty ? 0.0 : _currentIndex / _questions.length;

  /// Number of words whose every question was answered correctly.
  int get wordsMastered =>
      _wordProgress.values.where((w) => w.correct == w.questionCount).length;

  /// Load due words and build the question deck.
  Future<void> startQuizSession({int wordTarget = _defaultWordTarget}) async {
    _reset();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final dueResult = await getDueVocabularyUseCase(
        GetDueVocabularyParams(limit: wordTarget * 2),
      );

      await dueResult.fold(
        (failure) async {
          _errorMessage = failure.message;
          _isLoading = false;
          notifyListeners();
        },
        (dueList) async {
          if (dueList.isEmpty) {
            _errorMessage = 'No vocabulary due for review!';
            _isLoading = false;
            notifyListeners();
            return;
          }

          final selected = dueList.take(wordTarget).toList();
          final cards = await _loadCards(selected);
          await _finalizeWithCards(cards);
        },
      );
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Quiz the words inside a custom deck.
  Future<void> startDeckSession({
    required String deckId,
    int limit = _defaultWordTarget,
  }) async {
    _reset();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await vocabularyRepository.getDeckItems(deckId);
      await result.fold(
        (failure) async {
          _errorMessage = failure.message;
          _isLoading = false;
          notifyListeners();
        },
        (deckItems) async {
          if (deckItems.isEmpty) {
            _errorMessage = 'No vocabulary found in this deck!';
            _isLoading = false;
            notifyListeners();
            return;
          }
          final cards = await _loadCards(deckItems.take(limit).toList());
          await _finalizeWithCards(cards);
        },
      );
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Quiz the words belonging to a topic (tag), adding them to the user's
  /// collection on the fly so reviews can be persisted.
  Future<void> startTopicSession({
    required String tag,
    int limit = _defaultWordTarget,
  }) async {
    _reset();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final itemsResult = await vocabularyRepository.getVocabularyItems(
        tag: tag,
        limit: limit,
      );
      await itemsResult.fold(
        (failure) async {
          _errorMessage = failure.message;
          _isLoading = false;
          notifyListeners();
        },
        (vocabItems) async {
          if (vocabItems.isEmpty) {
            _errorMessage = 'No vocabulary found for topic: $tag';
            _isLoading = false;
            notifyListeners();
            return;
          }

          final collectionResult =
              await vocabularyRepository.getUserCollection(limit: 200);
          final collectionMap = collectionResult.fold(
            (failure) => <String, UserVocabularyEntity>{},
            (collection) => {for (final uc in collection) uc.vocabularyId: uc},
          );

          final cardFutures = vocabItems.map((item) async {
            var userVocab = collectionMap[item.id];
            if (userVocab == null) {
              final added = await vocabularyRepository.addToCollection(item.id);
              userVocab = added.fold((failure) => null, (uv) => uv);
            }
            if (userVocab == null) return null;
            return ReviewCardEntity(
              userVocabulary: userVocab,
              vocabularyItem: item,
            );
          });
          final cards =
              (await Future.wait(cardFutures)).whereType<ReviewCardEntity>().toList();
          await _finalizeWithCards(cards);
        },
      );
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Build the distractor pool and question deck from prepared cards, then
  /// publish the session (or an error when nothing usable was produced).
  Future<void> _finalizeWithCards(List<ReviewCardEntity> cards) async {
    if (cards.isEmpty) {
      _errorMessage = 'Failed to load vocabulary items';
      _isLoading = false;
      notifyListeners();
      return;
    }

    final pool = await _loadDistractorPool(cards);
    _buildQuestions(cards, pool);

    if (_questions.isEmpty) {
      _errorMessage = 'Not enough vocabulary to build a quiz yet';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _wordCount = cards.length;
    _startedAt = DateTime.now();
    _questionStartTime = DateTime.now();
    _isLoading = false;
    notifyListeners();
  }

  Future<List<ReviewCardEntity>> _loadCards(
    List<UserVocabularyEntity> userVocabs,
  ) async {
    final futures = userVocabs.map((uv) async {
      final result = await vocabularyRepository.getVocabularyItem(
        uv.vocabularyId,
      );
      return result.fold<ReviewCardEntity?>(
        (failure) => null,
        (item) => ReviewCardEntity(userVocabulary: uv, vocabularyItem: item),
      );
    });
    final results = await Future.wait(futures);
    return results.whereType<ReviewCardEntity>().toList();
  }

  /// Master items used as wrong-answer choices. Falls back to the quiz cards
  /// themselves when the master list is unavailable.
  Future<List<VocabularyItemEntity>> _loadDistractorPool(
    List<ReviewCardEntity> cards,
  ) async {
    final pool = <String, VocabularyItemEntity>{
      for (final c in cards) c.vocabularyItem.id: c.vocabularyItem,
    };

    final result = await vocabularyRepository.getVocabularyItems(
      limit: _distractorPoolSize,
    );
    result.fold(
      (failure) => debugPrint('Quiz distractor pool failed: ${failure.message}'),
      (items) {
        for (final item in items) {
          pool[item.id] = item;
        }
      },
    );
    return pool.values.toList();
  }

  void _buildQuestions(
    List<ReviewCardEntity> cards,
    List<VocabularyItemEntity> pool,
  ) {
    final questions = <QuizQuestionEntity>[];

    for (final card in cards) {
      final built = <QuizQuestionEntity>[];
      final termToMeaning =
          _buildQuestion(card, pool, QuizDirection.termToMeaning);
      if (termToMeaning != null) built.add(termToMeaning);
      final meaningToTerm =
          _buildQuestion(card, pool, QuizDirection.meaningToTerm);
      if (meaningToTerm != null) built.add(meaningToTerm);

      if (built.isNotEmpty) {
        _wordProgress[card.userVocabulary.id] = _WordProgress(
          card: card,
          questionCount: built.length,
        );
        questions.addAll(built);
      }
    }

    _questions = _interleave(questions);
  }

  QuizQuestionEntity? _buildQuestion(
    ReviewCardEntity card,
    List<VocabularyItemEntity> pool,
    QuizDirection direction,
  ) {
    final item = card.vocabularyItem;
    final correctWord = item.word.trim();
    final correctMeaning = _meaningOf(item);
    if (correctWord.isEmpty || correctMeaning.isEmpty) return null;

    final String prompt;
    final String correctText;
    final List<String> distractorSource;

    if (direction == QuizDirection.termToMeaning) {
      prompt = correctWord;
      correctText = correctMeaning;
      distractorSource = pool
          .where((p) => p.id != item.id)
          .map(_meaningOf)
          .where((m) => m.isNotEmpty && m != correctMeaning)
          .toList();
    } else {
      prompt = correctMeaning;
      correctText = correctWord;
      distractorSource = pool
          .where((p) => p.id != item.id)
          .map((p) => p.word.trim())
          .where((w) => w.isNotEmpty && w != correctWord)
          .toList();
    }

    final distractors = _pickDistinct(distractorSource, _optionsPerQuestion - 1);
    if (distractors.isEmpty) return null; // need at least one wrong choice

    final options = <QuizOption>[
      QuizOption(text: correctText, isCorrect: true),
      ...distractors.map((d) => QuizOption(text: d, isCorrect: false)),
    ]..shuffle(_random);

    return QuizQuestionEntity(
      card: card,
      direction: direction,
      prompt: prompt,
      options: options,
    );
  }

  String _meaningOf(VocabularyItemEntity item) {
    final definition = item.definition.trim();
    return definition;
  }

  List<String> _pickDistinct(List<String> source, int count) {
    final unique = source.toSet().toList()..shuffle(_random);
    return unique.take(count).toList();
  }

  /// Spread a word's two questions apart so the answer isn't shown back-to-back.
  List<QuizQuestionEntity> _interleave(List<QuizQuestionEntity> questions) {
    final byWord = <String, List<QuizQuestionEntity>>{};
    for (final q in questions) {
      byWord.putIfAbsent(q.card.userVocabulary.id, () => []).add(q);
    }

    final result = <QuizQuestionEntity>[];
    var added = true;
    var round = 0;
    while (added) {
      added = false;
      for (final group in byWord.values) {
        if (round < group.length) {
          result.add(group[round]);
          added = true;
        }
      }
      round++;
    }
    return result;
  }

  /// Record the user's choice. UI feedback is shown immediately; the word's
  /// review is submitted in the background once all its questions are answered.
  void answer(int optionIndex) {
    if (_selectedIndex != null) return;
    final question = currentQuestion;
    if (question == null) return;

    _selectedIndex = optionIndex;
    final isCorrect = question.options[optionIndex].isCorrect;

    final progress = _wordProgress[question.card.userVocabulary.id];
    if (progress != null) {
      progress.answered++;
      if (isCorrect) progress.correct++;
      progress.timeSpentMs += _questionStartTime != null
          ? DateTime.now().difference(_questionStartTime!).inMilliseconds
          : 0;

      if (progress.answered >= progress.questionCount && !progress.submitted) {
        progress.submitted = true;
        _pendingSubmits.add(_submitWord(progress));
      }
    }

    notifyListeners();
  }

  /// Await any in-flight review submissions so the summary reflects all XP.
  Future<void> finishPending() async {
    if (_pendingSubmits.isEmpty) return;
    await Future.wait(_pendingSubmits);
    _pendingSubmits.clear();
  }

  Future<void> _submitWord(_WordProgress progress) async {
    final quality = _qualityFor(progress);
    final result = await submitReviewUseCase(
      SubmitReviewParams(
        userVocabularyId: progress.card.userVocabulary.id,
        quality: quality,
        timeSpentMs: progress.timeSpentMs,
      ),
    );
    result.fold(
      (failure) => debugPrint('Quiz review submit failed: ${failure.message}'),
      (review) => _totalXpEarned += review.xpEarned,
    );
  }

  ReviewQuality _qualityFor(_WordProgress progress) {
    if (progress.correct >= progress.questionCount) return ReviewQuality.easy;
    if (progress.correct > 0) return ReviewQuality.good;
    return ReviewQuality.incorrect;
  }

  /// Advance to the next question (or completion).
  void next() {
    if (_selectedIndex == null) return;
    _selectedIndex = null;
    _currentIndex++;
    _questionStartTime = DateTime.now();
    notifyListeners();
  }

  /// Build a session summary compatible with the shared complete screen.
  ReviewSessionEntity buildSummary() {
    return ReviewSessionEntity(
      cards: const [],
      startedAt: _startedAt ?? DateTime.now(),
      completedAt: DateTime.now(),
      totalCards: _wordCount,
      reviewedCards: _wordCount,
      correctCount: wordsMastered,
      totalXpEarned: _totalXpEarned,
    );
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _reset() {
    _questions = [];
    _currentIndex = 0;
    _selectedIndex = null;
    _wordProgress.clear();
    _pendingSubmits.clear();
    _questionStartTime = null;
    _startedAt = null;
    _wordCount = 0;
    _totalXpEarned = 0;
  }
}
