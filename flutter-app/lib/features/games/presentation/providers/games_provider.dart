import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/repositories/games_repository.dart';
import '../../domain/entities/game_entities.dart';

/// State management for English Games + XP System.
///
/// Phase 3: English Games.
class GamesProvider extends ChangeNotifier {
  final GamesRepository _repository;

  GamesProvider({GamesRepository? repository})
    : _repository = repository ?? GamesRepository();

  // ── Common State ──────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _error;
  String _selectedLevel = 'B1';
  GameType? _currentGame;
  DateTime? _gameStartTime;

  // ── Game Data State ───────────────────────────────────────────────────────
  WordScrambleGame? _wordScramble;
  FillBlankGame? _fillBlank;
  MatchingGame? _matching;
  SpellingBeeGame? _spellingBee;
  GrammarQuizGame? _grammarQuiz;
  HangmanGame? _hangman;

  // ── XP/Profile State ──────────────────────────────────────────────────────
  XPProfile? _xpProfile;
  XPAwardResult? _lastXPResult;
  List<LeaderboardUser> _leaderboard = [];
  Map<String, dynamic>? _currentUserLeaderboard;

  // ── Game Result ───────────────────────────────────────────────────────────
  GameResult? _lastGameResult;

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedLevel => _selectedLevel;
  GameType? get currentGame => _currentGame;

  WordScrambleGame? get wordScramble => _wordScramble;
  FillBlankGame? get fillBlank => _fillBlank;
  MatchingGame? get matching => _matching;
  SpellingBeeGame? get spellingBee => _spellingBee;
  GrammarQuizGame? get grammarQuiz => _grammarQuiz;
  HangmanGame? get hangman => _hangman;

  XPProfile? get xpProfile => _xpProfile;
  XPAwardResult? get lastXPResult => _lastXPResult;
  List<LeaderboardUser> get leaderboard => _leaderboard;
  Map<String, dynamic>? get currentUserLeaderboard => _currentUserLeaderboard;
  GameResult? get lastGameResult => _lastGameResult;

  int get totalXp => _xpProfile?.totalXp ?? 0;
  int get numericLevel => _xpProfile?.numericLevel ?? 1;
  double get levelProgress => _xpProfile?.levelProgressPercent ?? 0;
  int get streakDays => _xpProfile?.streakDays ?? 0;
  int get dailyXpToday => _xpProfile?.dailyXpToday ?? 0;
  int get dailyCapRemaining => _xpProfile?.dailyCapRemaining ?? 500;

  // ── Level Selection ───────────────────────────────────────────────────────

  void setLevel(String level) {
    _selectedLevel = level;
    notifyListeners();
  }

  // ── Load XP Profile ───────────────────────────────────────────────────────

  Future<void> loadXPProfile() async {
    _setLoading(true);
    try {
      _xpProfile = await _repository.getXPProfile();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ── Load Leaderboard ──────────────────────────────────────────────────────

  Future<void> loadLeaderboard() async {
    try {
      final result = await _repository.getLeaderboard();
      _leaderboard = (result['entries'] as List<dynamic>? ?? [])
          .map((e) => LeaderboardUser.fromJson(e as Map<String, dynamic>))
          .toList();
      _currentUserLeaderboard = result['current_user'] as Map<String, dynamic>?;
      notifyListeners();
    } catch (e) {
      // Non-critical — just log
      debugPrint('Leaderboard load error: $e');
    }
  }

  // ── Game Loading ──────────────────────────────────────────────────────────

  Future<void> loadWordScramble({int count = 10}) async {
    _setLoading(true);
    _currentGame = GameType.wordScramble;
    try {
      _wordScramble = await _repository.getWordScramble(
        level: _selectedLevel,
        count: count,
      );
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadFillBlank({int count = 8}) async {
    _setLoading(true);
    _currentGame = GameType.fillBlank;
    try {
      _fillBlank = await _repository.getFillBlank(
        level: _selectedLevel,
        count: count,
      );
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadMatchingGame({String variation = 'definition'}) async {
    _setLoading(true);
    _currentGame = GameType.matching;
    try {
      _matching = await _repository.getMatchingGame(
        level: _selectedLevel,
        variation: variation,
      );
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadSpellingBee({int count = 8}) async {
    _setLoading(true);
    _currentGame = GameType.spellingBee;
    try {
      _spellingBee = await _repository.getSpellingBee(
        level: _selectedLevel,
        count: count,
      );
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadGrammarQuiz({String? topic, int count = 10}) async {
    _setLoading(true);
    _currentGame = GameType.grammarQuiz;
    try {
      _grammarQuiz = await _repository.getGrammarQuiz(
        level: _selectedLevel,
        topic: topic,
        count: count,
      );
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadHangman({String? category}) async {
    _setLoading(true);
    _currentGame = GameType.hangman;
    try {
      _hangman = await _repository.getHangmanGame(
        level: _selectedLevel,
        category: category,
      );
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ── Game Completion & XP Award ────────────────────────────────────────────

  /// Called when a game session ends. Awards XP and records result.
  Future<XPAwardResult?> completeGame({
    required GameType gameType,
    required int score,
    required int totalQuestions,
    required int correctAnswers,
    required int baseXp,
    String? sessionId,
  }) async {
    final durationSeconds = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inSeconds
        : null;

    // Record local result
    _lastGameResult = GameResult(
      gameType: gameType,
      cefrLevel: _selectedLevel,
      score: score,
      totalQuestions: totalQuestions,
      correctAnswers: correctAnswers,
      xpEarned: baseXp,
      durationSeconds: durationSeconds ?? 0,
    );

    // Award XP via backend
    try {
      final result = await _repository.awardXP(
        source: 'game',
        baseXp: baseXp,
        sourceId: sessionId,
        sourceDetail: gameType.apiKey,
        durationSeconds: durationSeconds,
        score: correctAnswers,
        totalQuestions: totalQuestions,
      );
      _lastXPResult = result;

      // Update local XP snapshot
      if (_xpProfile != null) {
        _xpProfile = XPProfile(
          userId: _xpProfile!.userId,
          totalXp: result.newTotalXp,
          numericLevel: result.newLevel,
          levelProgressPercent: result.levelProgressPercent,
          xpForNextLevel: result.xpForNextLevel,
          currentXpInLevel: _xpProfile!.currentXpInLevel,
          dailyXpToday: result.dailyXpToday,
          dailyCapRemaining: result.dailyCapRemaining,
          streakDays: result.streakDays,
          bestStreak: _xpProfile!.bestStreak,
          recentTransactions: _xpProfile!.recentTransactions,
        );
      }

      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('XP award error: $e');
      notifyListeners();
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearLastResult() {
    _lastGameResult = null;
    _lastXPResult = null;
    notifyListeners();
  }
}
