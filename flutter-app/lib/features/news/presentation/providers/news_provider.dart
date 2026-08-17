import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/services/skill_event_recorder.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

import '../../data/repositories/news_repository.dart';
import '../../domain/entities/news_entities.dart';

/// State management for News Reading feature.
///
/// Phase 2: News Reading.
class NewsProvider extends ChangeNotifier {
  final NewsRepository _repository;
  final MistakeNotebookRepository _mistakeRepository;
  final SkillEventRecorder _skillRecorder;

  NewsProvider({
    NewsRepository? repository,
    MistakeNotebookRepository? mistakeRepository,
    SkillEventRecorder? skillRecorder,
  }) : _repository = repository ?? NewsRepository(),
       _mistakeRepository =
           mistakeRepository ?? const MistakeNotebookRepository(),
       _skillRecorder = skillRecorder ?? const SkillEventRecorder();

  // ── State ──
  List<NewsArticle> _articles = [];
  List<NewsCategory> _categories = [];
  NewsQuiz? _currentQuiz;
  String? _currentQuizArticleId;
  NewsArticle? _currentQuizArticle;
  bool _isLoading = false;
  bool _isLoadingQuiz = false;
  String? _error;
  String _selectedCategory = 'general';
  String? _selectedLevel;
  int _currentPage = 1;

  // Quiz state
  Map<int, int> _answers = {}; // questionId → selectedIndex
  bool _quizSubmitted = false;

  // ── Getters ──
  List<NewsArticle> get articles => _articles;
  List<NewsCategory> get categories => _categories;
  NewsQuiz? get currentQuiz => _currentQuiz;
  bool get isLoading => _isLoading;
  bool get isLoadingQuiz => _isLoadingQuiz;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  String? get selectedLevel => _selectedLevel;
  Map<int, int> get answers => _answers;
  bool get quizSubmitted => _quizSubmitted;

  int get quizScore {
    if (_currentQuiz == null || !_quizSubmitted) return 0;
    int correct = 0;
    for (final question in _currentQuiz!.questions) {
      if (_answers[question.id] == question.correctIndex) correct++;
    }
    return correct;
  }

  int get quizTotal => _currentQuiz?.totalQuestions ?? 0;

  // ── Actions ──

  /// Load articles for the selected category and level.
  Future<void> loadArticles({bool refresh = false}) async {
    if (refresh) _currentPage = 1;

    _isLoading = true;
    _error = null;
    if (refresh) _articles = [];
    notifyListeners();

    try {
      final result = await _repository.getArticles(
        category: _selectedCategory,
        level: _selectedLevel,
        page: _currentPage,
      );
      if (refresh || _currentPage == 1) {
        _articles = result;
      } else {
        _articles.addAll(result);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load available categories.
  Future<void> loadCategories() async {
    try {
      _categories = await _repository.getCategories();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
  }

  /// Change selected category and reload.
  Future<void> selectCategory(String category) async {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    await loadArticles(refresh: true);
  }

  /// Change selected CEFR level filter and reload.
  Future<void> selectLevel(String? level) async {
    if (_selectedLevel == level) return;
    _selectedLevel = level;
    await loadArticles(refresh: true);
  }

  /// Search articles.
  Future<void> searchArticles(String query) async {
    if (query.length < 2) return;

    _isLoading = true;
    _error = null;
    _articles = [];
    notifyListeners();

    try {
      _articles = await _repository.getArticles(query: query);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load next page of articles.
  Future<void> loadMore() async {
    if (_isLoading) return;
    _currentPage++;
    await loadArticles();
  }

  // ── Quiz ──

  /// Load quiz for an article.
  Future<void> loadQuiz(String articleId, {NewsArticle? article}) async {
    _isLoadingQuiz = true;
    _currentQuiz = null;
    _currentQuizArticleId = articleId;
    _currentQuizArticle = article ?? _findArticle(articleId);
    _answers = {};
    _quizSubmitted = false;
    notifyListeners();

    try {
      _currentQuiz = await _repository.getQuiz(articleId);
    } catch (e) {
      debugPrint('Failed to load quiz: $e');
    } finally {
      _isLoadingQuiz = false;
      notifyListeners();
    }
  }

  /// Record answer for a quiz question.
  void answerQuestion(int questionId, int selectedIndex) {
    if (_quizSubmitted) return;
    _answers[questionId] = selectedIndex;
    notifyListeners();
  }

  /// Submit quiz and calculate score.
  void submitQuiz() {
    if (_quizSubmitted) return;
    _recordSubmittedMistakes();
    unawaited(_recordSubmittedSkillEvents());
    _quizSubmitted = true;
    notifyListeners();
  }

  /// Reset quiz state.
  void resetQuiz() {
    _currentQuiz = null;
    _currentQuizArticleId = null;
    _currentQuizArticle = null;
    _answers = {};
    _quizSubmitted = false;
    notifyListeners();
  }

  /// Clear all state.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Fetch full article content from the original URL.
  /// Returns the full text or null if scraping fails.
  Future<String?> loadFullContent(String articleUrl) async {
    try {
      return await _repository.getFullContent(articleUrl);
    } catch (e) {
      debugPrint('Failed to load full article content: $e');
      return null;
    }
  }

  NewsArticle? _findArticle(String articleId) {
    for (final article in _articles) {
      if (article.id == articleId) return article;
    }
    return null;
  }

  /// Which skill a news quiz question exercises. The API tags questions
  /// "comprehension", "vocabulary" or "grammar"; comprehension of an article
  /// is reading, and an unrecognised tag is treated the same way rather than
  /// silently crediting vocabulary.
  static SkillType _skillForQuestion(String type) {
    switch (type.trim().toLowerCase()) {
      case 'vocabulary':
        return SkillType.vocabulary;
      case 'grammar':
        return SkillType.grammar;
      default:
        return SkillType.reading;
    }
  }

  Future<void> _recordSubmittedSkillEvents() async {
    final quiz = _currentQuiz;
    if (quiz == null) return;

    final level = normalizeCefrLevel(_currentQuizArticle?.cefrLevel);
    final results = <ExerciseResultData>[];

    for (final question in quiz.questions) {
      final selectedIndex = _answers[question.id];
      if (selectedIndex == null) continue; // unanswered is not evidence
      final isCorrect = selectedIndex == question.correctIndex;
      results.add(
        ExerciseResultData(
          exerciseType: 'news_quiz',
          skill: _skillForQuestion(question.type),
          difficultyLevel: level,
          isCorrect: isCorrect,
          score: isCorrect ? 100 : 0,
        ),
      );
    }

    await _skillRecorder.record(results);
  }

  void _recordSubmittedMistakes() {
    final quiz = _currentQuiz;
    if (quiz == null) return;

    final article = _currentQuizArticle;
    final sourceId = article?.id ?? _currentQuizArticleId ?? 'news_quiz';
    final sourceTitle = article?.title ?? 'News quiz';

    for (final question in quiz.questions) {
      final selectedIndex = _answers[question.id];
      if (selectedIndex == null || selectedIndex == question.correctIndex) {
        continue;
      }

      final selectedAnswer = _optionText(question.options, selectedIndex);
      final correctAnswer = _optionText(
        question.options,
        question.correctIndex,
      );

      unawaited(
        _mistakeRepository.saveMistake(
          MistakeNotebookEntry(
            id: MistakeNotebookEntry.buildId(
              sourceType: 'news_quiz',
              sourceId: sourceId,
              questionId: '${question.id}:${question.question}',
              selectedAnswer: selectedAnswer,
            ),
            sourceType: 'news_quiz',
            sourceId: sourceId,
            sourceTitle: sourceTitle,
            question: question.question,
            selectedAnswer: selectedAnswer,
            correctAnswer: correctAnswer,
            explanation: question.explanation,
            skill: question.type.isEmpty ? 'reading' : question.type,
            createdAt: DateTime.now(),
          ),
        ),
      );
    }
  }

  String _optionText(List<String> options, int index) {
    if (index < 0 || index >= options.length) return '';
    return options[index];
  }
}
