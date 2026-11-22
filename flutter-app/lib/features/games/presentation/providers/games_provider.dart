import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/repositories/games_repository.dart';
import '../../domain/entities/game_entities.dart';
import 'package:lexilingo_app/core/state/reset_epoch.dart';

enum GameAwardStatus { idle, submitting, awarded, failed, alreadyAwarded }

class _PendingGameCompletion {
  final String sessionId;
  final List<Map<String, String>> answers;
  final int? durationSeconds;
  final int hintsUsed;
  final List<String> rescuedIds;

  const _PendingGameCompletion({
    required this.sessionId,
    required this.answers,
    required this.durationSeconds,
    required this.hintsUsed,
    required this.rescuedIds,
  });
}

/// State management for English Games + XP System.
///
/// Phase 3: English Games.
class GamesProvider extends ChangeNotifier with ResetEpoch {
  final GamesRepository _repository;

  GamesProvider({GamesRepository? repository})
    : _repository = repository ?? GamesRepository();

  // ── Common State ──────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _error;
  String _selectedLevel = 'A1';
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
  GameAwardStatus _awardStatus = GameAwardStatus.idle;
  String? _awardError;
  _PendingGameCompletion? _pendingCompletion;
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
  GameAwardStatus get awardStatus => _awardStatus;
  String? get awardError => _awardError;
  bool get isAwardSubmitting => _awardStatus == GameAwardStatus.submitting;
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
    final epoch = resetEpoch;
    _setLoading(true);
    try {
      final loaded = await _repository.getXPProfile();
      if (isStale(epoch)) return;
      _xpProfile = loaded;
      _error = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) _setLoading(false);
    }
  }

  // ── Load Leaderboard ──────────────────────────────────────────────────────

  Future<void> loadLeaderboard() async {
    final epoch = resetEpoch;
    try {
      final result = await _repository.getLeaderboard();
      if (isStale(epoch)) return;
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
    _resetAwardState();
    _wordScramble = null;
    final epoch = resetEpoch;
    _setLoading(true);
    _currentGame = GameType.wordScramble;
    try {
      final loaded = await _repository.getWordScramble(
        level: _selectedLevel,
        count: count,
      );
      if (isStale(epoch)) return;
      _wordScramble = loaded;
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) _setLoading(false);
    }
  }

  Future<void> loadFillBlank({int count = 8}) async {
    _resetAwardState();
    _fillBlank = null;
    final epoch = resetEpoch;
    _setLoading(true);
    _currentGame = GameType.fillBlank;
    try {
      final loaded = await _repository.getFillBlank(
        level: _selectedLevel,
        count: count,
      );
      if (isStale(epoch)) return;
      _fillBlank = loaded;
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) _setLoading(false);
    }
  }

  Future<void> loadMatchingGame({String variant = 'definition'}) async {
    _resetAwardState();
    _matching = null;
    final epoch = resetEpoch;
    _setLoading(true);
    _currentGame = GameType.matching;
    try {
      final loaded = await _repository.getMatchingGame(
        level: _selectedLevel,
        variant: variant,
      );
      if (isStale(epoch)) return;
      _matching = loaded;
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) _setLoading(false);
    }
  }

  Future<void> loadSpellingBee({int count = 8}) async {
    _resetAwardState();
    _spellingBee = null;
    final epoch = resetEpoch;
    _setLoading(true);
    _currentGame = GameType.spellingBee;
    try {
      final loaded = await _repository.getSpellingBee(
        level: _selectedLevel,
        count: count,
      );
      if (isStale(epoch)) return;
      _spellingBee = loaded;
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) _setLoading(false);
    }
  }

  Future<void> loadGrammarQuiz({String? topic, int count = 10}) async {
    _resetAwardState();
    _grammarQuiz = null;
    final epoch = resetEpoch;
    _setLoading(true);
    _currentGame = GameType.grammarQuiz;
    try {
      final loaded = await _repository.getGrammarQuiz(
        level: _selectedLevel,
        topic: topic,
        count: count,
      );
      if (isStale(epoch)) return;
      _grammarQuiz = loaded;
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) _setLoading(false);
    }
  }

  Future<void> loadHangman({String? category}) async {
    _resetAwardState();
    _hangman = null;
    final epoch = resetEpoch;
    _setLoading(true);
    _currentGame = GameType.hangman;
    try {
      final loaded = await _repository.getHangmanGame(
        level: _selectedLevel,
        category: category,
      );
      if (isStale(epoch)) return;
      _hangman = loaded;
      _gameStartTime = DateTime.now();
      _error = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) _setLoading(false);
    }
  }

  // ── Game Completion & XP Award ────────────────────────────────────────────

  /// Called when a game session ends. Awards XP and records result.
  Future<XPAwardResult?> completeGame({
    required GameType gameType,
    required int score,
    required int totalQuestions,
    required int correctAnswers,
    required List<Map<String, String>> answers,
    String? sessionId,
    int hintsUsed = 0,
    List<String> rescuedIds = const [],
  }) async {
    if (_awardStatus == GameAwardStatus.submitting) return null;
    if (_awardStatus == GameAwardStatus.awarded && _lastXPResult != null) {
      _awardStatus = GameAwardStatus.alreadyAwarded;
      notifyListeners();
      return _lastXPResult;
    }

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
      xpEarned: 0,
      durationSeconds: durationSeconds ?? 0,
    );

    final resolvedSessionId = sessionId ?? _sessionIdFor(gameType);
    if (resolvedSessionId.isEmpty) {
      _awardStatus = GameAwardStatus.failed;
      _awardError = 'Missing game session ID for ${gameType.apiKey}';
      notifyListeners();
      return null;
    }

    _pendingCompletion = _PendingGameCompletion(
      sessionId: resolvedSessionId,
      answers: answers
          .map((answer) => Map<String, String>.from(answer))
          .toList(),
      durationSeconds: durationSeconds,
      hintsUsed: hintsUsed,
      rescuedIds: List<String>.from(rescuedIds),
    );
    return _submitPendingCompletion();
  }

  Future<XPAwardResult?> retryLastCompletion() async {
    if (_pendingCompletion == null ||
        _awardStatus == GameAwardStatus.submitting ||
        _awardStatus == GameAwardStatus.awarded) {
      return _lastXPResult;
    }
    return _submitPendingCompletion();
  }

  Future<XPAwardResult?> _submitPendingCompletion() async {
    final pending = _pendingCompletion;
    if (pending == null) return null;

    final epoch = resetEpoch;
    _awardStatus = GameAwardStatus.submitting;
    _awardError = null;
    notifyListeners();
    try {
      final result = await _repository.completeGameSession(
        sessionId: pending.sessionId,
        answers: pending.answers,
        clientDurationSeconds: pending.durationSeconds,
        hintsUsed: pending.hintsUsed,
        rescuedIds: pending.rescuedIds,
      );
      if (isStale(epoch)) return null;
      _lastXPResult = result;
      _awardStatus = GameAwardStatus.awarded;
      if (_lastGameResult != null) {
        _lastGameResult = _lastGameResult!.copyWith(xpEarned: result.xpAwarded);
      }
      if (_xpProfile != null) {
        _xpProfile = _xpProfile!.copyWith(
          totalXp: result.newTotalXp,
          numericLevel: result.newLevel,
          levelProgressPercent: result.levelProgressPercent,
          xpForNextLevel: result.xpForNextLevel,
          currentXpInLevel: result.currentXpInLevel,
          dailyXpToday: result.dailyXpToday,
          dailyCapRemaining: result.dailyCapRemaining,
          streakDays: result.streakDays,
        );
      }
      return result;
    } catch (e) {
      if (isStale(epoch)) return null;
      _awardStatus = GameAwardStatus.failed;
      _awardError = e.toString();
      debugPrint('XP award error: $e');
      return null;
    } finally {
      notifyListeners();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String sessionIdFor(GameType gameType) => _sessionIdFor(gameType);

  String _sessionIdFor(GameType gameType) => switch (gameType) {
    GameType.wordScramble => _wordScramble?.sessionId ?? '',
    GameType.fillBlank => _fillBlank?.sessionId ?? '',
    GameType.matching => _matching?.sessionId ?? '',
    GameType.spellingBee => _spellingBee?.sessionId ?? '',
    GameType.grammarQuiz => _grammarQuiz?.sessionId ?? '',
    GameType.hangman => _hangman?.sessionId ?? '',
  };

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _resetAwardState() {
    _lastXPResult = null;
    _awardStatus = GameAwardStatus.idle;
    _awardError = null;
    _pendingCompletion = null;
  }

  void reset() {
    bumpResetEpoch();
    _isLoading = false;
    _error = null;
    _selectedLevel = 'A1';
    _currentGame = null;
    _gameStartTime = null;
    _wordScramble = null;
    _fillBlank = null;
    _matching = null;
    _spellingBee = null;
    _grammarQuiz = null;
    _hangman = null;
    _xpProfile = null;
    _leaderboard = [];
    _currentUserLeaderboard = null;
    _lastGameResult = null;
    _resetAwardState();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearLastResult() {
    _lastGameResult = null;
    _lastXPResult = null;
    _awardStatus = GameAwardStatus.idle;
    _awardError = null;
    _pendingCompletion = null;
    notifyListeners();
  }
}
