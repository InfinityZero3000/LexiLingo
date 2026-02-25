import 'package:flutter/foundation.dart';
import '../../data/repositories/news_repository.dart';
import '../../domain/entities/news_entities.dart';

/// State management for News Reading feature.
///
/// Phase 2: News Reading.
class NewsProvider extends ChangeNotifier {
  final NewsRepository _repository;

  NewsProvider({NewsRepository? repository})
    : _repository = repository ?? NewsRepository();

  // ── State ──
  List<NewsArticle> _articles = [];
  List<NewsCategory> _categories = [];
  NewsQuiz? _currentQuiz;
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
  Future<void> loadQuiz(String articleId) async {
    _isLoadingQuiz = true;
    _currentQuiz = null;
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
    _quizSubmitted = true;
    notifyListeners();
  }

  /// Reset quiz state.
  void resetQuiz() {
    _currentQuiz = null;
    _answers = {};
    _quizSubmitted = false;
    notifyListeners();
  }

  /// Clear all state.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
