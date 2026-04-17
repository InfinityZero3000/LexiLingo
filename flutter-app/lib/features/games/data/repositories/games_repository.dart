import '../../../../core/network/api_client.dart';
import '../../../../core/services/local_cache_service.dart';
import '../../domain/entities/game_entities.dart';

/// Repository for the Games feature — word games, XP system, and leaderboard.
///
/// Uses [ApiClient] for authenticated requests. The client handles JWT bearer
/// tokens, logging, and network error mapping automatically.
///
/// Two styles of methods are provided:
///   • Session methods  — return game container objects (WordScrambleGame,
///     MatchingGame, etc.) which include timer/XP config from the backend.
///   • Word-list methods — return plain lists of entity objects
///     (List<ScrambleWord>, MatchingGameData, etc.) for use when only the
///     word data is needed.
///
/// XP methods always bypass the cache (mutate server state).
class GamesRepository {
  final ApiClient _apiClient;
  final LocalCacheService _cache;

  GamesRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient(),
      _cache = LocalCacheService.instance;

  // ── Word Scramble ─────────────────────────────────────────────────────────

  /// Full session — includes timer config and XP settings.
  Future<WordScrambleGame> getWordScramble({
    String level = 'A2',
    int count = 10,
  }) async {
    final data = await _apiClient.get(
      '/games/word-scramble?level=$level&count=$count',
    );
    return WordScrambleGame.fromJson(data);
  }

  /// Word list only — lightweight alternative to [getWordScramble].
  ///
  /// GET /games/scramble?level=A1&count=10
  Future<List<ScrambleWord>> getScrambleWords({
    String level = 'A1',
    int count = 10,
  }) async {
    final data = await _apiClient.get(
      '/games/scramble?level=$level&count=$count',
    );
    return (data['words'] as List<dynamic>? ?? [])
        .map((w) => ScrambleWord.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  // ── Fill in the Blank ─────────────────────────────────────────────────────

  /// Full session — includes timer config and total XP.
  Future<FillBlankGame> getFillBlank({
    String level = 'B1',
    int count = 8,
  }) async {
    final data = await _apiClient.get(
      '/games/fill-blank?level=$level&count=$count',
    );
    return FillBlankGame.fromJson(data);
  }

  /// Question list only — lightweight alternative to [getFillBlank].
  ///
  /// GET /games/fill-blank?level=A1&count=8
  Future<List<FillBlankQuestion>> getFillBlankQuestions({
    String level = 'A1',
    int count = 8,
  }) async {
    final data = await _apiClient.get(
      '/games/fill-blank?level=$level&count=$count',
    );
    return (data['questions'] as List<dynamic>? ?? [])
        .map((q) => FillBlankQuestion.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  // ── Matching Game ─────────────────────────────────────────────────────────

  /// Full session — includes timer config and XP settings.
  Future<MatchingGame> getMatchingGame({
    String level = 'B1',
    String variation = 'definition',
  }) async {
    final data = await _apiClient.get(
      '/games/matching?level=$level&variation=$variation',
    );
    return MatchingGame.fromJson(data);
  }

  /// Two-column data only — lightweight alternative to [getMatchingGame].
  ///
  /// GET /games/matching?level=A1&count=6&variant=definition
  Future<MatchingGameData> getMatchingPairs({
    String level = 'A1',
    int count = 6,
    String variant = 'definition',
  }) async {
    final data = await _apiClient.get(
      '/games/matching?level=$level&count=$count&variant=$variant',
    );
    return MatchingGameData.fromJson(data);
  }

  // ── Spelling Bee ──────────────────────────────────────────────────────────

  /// Full session — includes timer config.
  Future<SpellingBeeGame> getSpellingBee({
    String level = 'B1',
    int count = 8,
  }) async {
    final data = await _apiClient.get(
      '/games/spelling-bee?level=$level&count=$count',
    );
    return SpellingBeeGame.fromJson(data);
  }

  /// Word list only — lightweight alternative to [getSpellingBee].
  ///
  /// GET /games/spelling-bee?level=A1&count=8
  Future<List<SpellingBeeWord>> getSpellingBeeWords({
    String level = 'A1',
    int count = 8,
  }) async {
    final data = await _apiClient.get(
      '/games/spelling-bee?level=$level&count=$count',
    );
    return (data['words'] as List<dynamic>? ?? [])
        .map((w) => SpellingBeeWord.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  // ── Grammar Quiz ──────────────────────────────────────────────────────────

  /// Full session — includes timer config and topic info.
  Future<GrammarQuizGame> getGrammarQuiz({
    String level = 'B1',
    String? topic,
    int count = 10,
  }) async {
    final query = StringBuffer('/games/grammar-quiz?level=$level&count=$count');
    if (topic != null) query.write('&topic=$topic');
    final data = await _apiClient.get(query.toString());
    return GrammarQuizGame.fromJson(data);
  }

  /// Question list only (API-aligned) — lightweight alternative to
  /// [getGrammarQuiz].
  ///
  /// GET /games/grammar-quiz?level=A1[&topic=tenses]&count=10
  Future<List<GrammarQuizQuestion>> getGrammarQuizQuestions({
    String level = 'A1',
    String? topic,
    int count = 10,
  }) async {
    final query = StringBuffer('/games/grammar-quiz?level=$level&count=$count');
    if (topic != null) query.write('&topic=$topic');
    final data = await _apiClient.get(query.toString());
    return (data['questions'] as List<dynamic>? ?? [])
        .map((q) => GrammarQuizQuestion.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  // ── Hangman ───────────────────────────────────────────────────────────────

  /// Full session — includes tiered hints and max-lives config.
  Future<HangmanGame> getHangmanGame({
    String level = 'A2',
    String? category,
  }) async {
    final query = StringBuffer('/games/hangman?level=$level');
    if (category != null) query.write('&category=$category');
    final data = await _apiClient.get(query.toString());
    return HangmanGame.fromJson(data);
  }

  /// Single word only (flat entity) — lightweight alternative to
  /// [getHangmanGame].
  ///
  /// GET /games/hangman?level=A1[&category=animals]
  Future<HangmanWord> getHangmanWord({
    String level = 'A1',
    String? category,
  }) async {
    final query = StringBuffer('/games/hangman?level=$level');
    if (category != null) query.write('&category=$category');
    final data = await _apiClient.get(query.toString());
    // Backend may wrap the word under a 'word' key or return it at root.
    final wordData = data['word'] as Map<String, dynamic>? ?? data;
    return HangmanWord.fromJson(wordData);
  }

  // ── XP System ─────────────────────────────────────────────────────────────

  /// Award XP to the current user after completing a game.
  ///
  /// POST /xp/award — always hits the network (mutates server state).
  ///
  /// [source] should match GameType.apiKey, e.g. 'word_scramble'.
  Future<XPAwardResult> awardXP({
    required String source,
    required int baseXp,
    String? sourceId,
    String? sourceDetail,
    int? durationSeconds,
    int? score,
    int? totalQuestions,
  }) async {
    final body = <String, dynamic>{
      'source': source,
      'base_xp': baseXp,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceDetail != null) 'source_detail': sourceDetail,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (score != null) 'score': score,
      if (totalQuestions != null) 'total_questions': totalQuestions,
    };
    final data = await _apiClient.post('/xp/award', body: body);
    await _cache.invalidate('xp:profile:v1');
    await _cache.invalidate('xp:leaderboard:limit:20');
    return XPAwardResult.fromJson(data);
  }

  /// Fetch the current user's XP profile.
  ///
  /// GET /xp/profile — local-first with short TTL to reduce repeated load.
  Future<XPProfile> getXPProfile() async {
    final cached = await _cache.getOrFetch(
      key: 'xp:profile:v1',
      type: 'game',
      fetchFn: () => _apiClient.get('/xp/profile'),
    );
    final data = cached ?? await _apiClient.get('/xp/profile');
    // Backend may wrap the profile under a 'profile' key or return it at root.
    final profileData = data['profile'] as Map<String, dynamic>? ?? data;
    return XPProfile.fromJson(profileData);
  }

  /// Fetch the XP leaderboard.
  ///
  /// GET /xp/leaderboard?limit=20
  ///
  /// Returns the raw JSON map. Parse entries with [LeaderboardEntry.fromJson]
  /// (new, includes isCurrentUser) or [LeaderboardUser.fromJson] (legacy).
  Future<Map<String, dynamic>> getLeaderboard({int limit = 20}) async {
    final cacheKey = 'xp:leaderboard:limit:$limit';
    final cached = await _cache.getOrFetch(
      key: cacheKey,
      type: 'game',
      fetchFn: () => _apiClient.get('/xp/leaderboard?limit=$limit'),
    );
    return cached ?? await _apiClient.get('/xp/leaderboard?limit=$limit');
  }
}
