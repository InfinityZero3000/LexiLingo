import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/services/local_cache_service.dart';
import '../../domain/entities/news_entities.dart';

/// Repository for News feature — handles API calls and local caching.
///
/// All calls go through the backend proxy (which handles NewsAPI key,
/// quota management, and server-side caching).
///
/// Phase 2: News Reading.
class NewsRepository {
  final http.Client _client;
  final LocalCacheService _cache;
  final ApiClient? _apiClient;

  NewsRepository({
    http.Client? client,
    LocalCacheService? cache,
    ApiClient? apiClient,
  }) : _client = client ?? http.Client(),
       _cache = cache ?? LocalCacheService.instance,
       _apiClient = apiClient;

  /// Award XP for a finished news quiz.
  ///
  /// `/proficiency/record-exercises` records the skill evidence but grants no
  /// XP — it takes a score graded on the device. XP goes through `/xp/award`
  /// instead, which caps per source, caps the day and dedups on `source_id`.
  /// Silently returns on failure: XP must never block the result screen.
  Future<void> awardQuizXp({
    required int baseXp,
    required String sourceId,
  }) async {
    final client = _apiClient;
    if (client == null) return;
    try {
      await client.post(
        '/xp/award',
        body: {
          'source': 'news',
          'base_xp': baseXp,
          'source_id': sourceId,
          'source_detail': 'news_quiz',
        },
      );
    } catch (e) {
      debugPrint('NewsRepository.awardQuizXp: $e');
    }
  }

  String get _baseUrl => '${ApiConfig.baseUrl}/news';

  // ──── Articles ────

  /// Get news articles, optionally filtered by category and CEFR level.
  Future<List<NewsArticle>> getArticles({
    String category = 'general',
    String? level,
    int page = 1,
    String? query,
  }) async {
    final params = {
      'category': category,
      'page': page.toString(),
      if (level != null) 'level': level,
      if (query != null) 'q': query,
    };
    final cacheKey =
        'news:articles:${params.entries.map((e) => '${e.key}:${e.value}').join(':')}';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'news',
      fetchFn: () async {
        final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
        final response = await _client.get(uri);
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return [];

    return (data['articles'] as List<dynamic>? ?? [])
        .map((a) => NewsArticle.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  // ──── Categories ────

  /// Get available news categories.
  Future<List<NewsCategory>> getCategories() async {
    final cacheKey = 'news:categories';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'news',
      fetchFn: () async {
        final uri = Uri.parse('$_baseUrl/categories');
        final response = await _client.get(uri);
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return [];

    return (data['categories'] as List<dynamic>? ?? [])
        .map((c) => NewsCategory.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  // ──── Quiz ────

  /// Get comprehension quiz for an article.
  Future<NewsQuiz?> getQuiz(String articleId) async {
    final cacheKey = 'news:quiz:$articleId';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'news',
      fetchFn: () async {
        final uri = Uri.parse('$_baseUrl/$articleId/quiz');
        final response = await _client.get(uri);
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return null;

    return NewsQuiz.fromJson(data);
  }

  // ──── Full Article Content ────

  /// Scrape full article content from the original URL.
  /// NewsAPI free tier truncates content to ~200 chars.
  Future<String?> getFullContent(String articleUrl) async {
    final cacheKey = 'news:full:$articleUrl';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'news',
      fetchFn: () async {
        final uri = Uri.parse('$_baseUrl/full-content');
        final response = await _client.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'url': articleUrl}),
        );
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    return data?['content'] as String?;
  }

  // ──── Helpers ────

  void _checkResponse(http.Response response) {
    if (response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }
  }
}
