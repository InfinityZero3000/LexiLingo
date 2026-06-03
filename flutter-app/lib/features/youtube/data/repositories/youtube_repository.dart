import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_config.dart';
import '../../../../core/services/local_cache_service.dart';
import '../../domain/entities/youtube_entities.dart';

/// Repository for YouTube feature — handles API calls and caching.
///
/// All calls go through the backend proxy (which handles YouTube API key,
/// quota management, and server-side caching).
///
/// Phase 1: YouTube Video Integration.
class YouTubeRepository {
  final http.Client _client;
  final LocalCacheService _cache;

  YouTubeRepository({http.Client? client, LocalCacheService? cache})
    : _client = client ?? http.Client(),
      _cache = cache ?? LocalCacheService.instance;

  String get _baseUrl => '${ApiConfig.baseUrl}/youtube';

  // ──── Curated Channels (No API cost) ────

  /// Get curated English learning YouTube channels.
  Future<List<YouTubeChannel>> getCuratedChannels({String? category}) async {
    // v4: bumped to force re-fetch after thumbnail proxy was fixed server-side.
    final cacheKey = 'youtube:channels:v4${category != null ? ':$category' : ''}';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'youtube',
      fetchFn: () async {
        final uri = Uri.parse('$_baseUrl/channels').replace(
          queryParameters: {if (category != null) 'category': category},
        );
        final response = await _client.get(uri);
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return [];

    return (data['channels'] as List<dynamic>? ?? [])
        .map((c) => YouTubeChannel.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  // ──── Video Search (100 units) ────

  /// Search for YouTube videos.
  Future<YouTubeSearchResult> searchVideos({
    required String query,
    int maxResults = 10,
    String? channelId,
    String? pageToken,
  }) async {
    final params = {
      'q': query,
      'max_results': maxResults.toString(),
      if (channelId != null) 'channel_id': channelId,
      if (pageToken != null) 'page_token': pageToken,
    };
    final cacheKey =
        'youtube:search:${params.entries.map((e) => '${e.key}:${e.value}').join(':')}';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'youtube',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/search',
        ).replace(queryParameters: params);
        final response = await _client.get(uri);
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) {
      return const YouTubeSearchResult(videos: [], totalResults: 0);
    }

    return YouTubeSearchResult.fromJson(data);
  }

  // ──── Captions (permanent cache) ────

  /// Get captions/subtitles for a video.
  Future<List<CaptionSegment>> getCaptions(
    String videoId, {
    String lang = 'en',
  }) async {
    final cacheKey = 'youtube:captions:$videoId:$lang';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'youtube',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/captions/$videoId',
        ).replace(queryParameters: {'lang': lang});
        final response = await _client.get(uri);
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return [];

    return (data['segments'] as List<dynamic>? ?? [])
        .map((s) => CaptionSegment.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ──── Channel Videos ────

  /// Get latest videos from a specific channel.
  Future<YouTubeSearchResult> getChannelVideos(
    String channelId, {
    int maxResults = 10,
    String? pageToken,
  }) async {
    final params = {
      'max_results': maxResults.toString(),
      if (pageToken != null) 'page_token': pageToken,
    };
    final cacheKey =
        'youtube:channel_videos:$channelId:${params.values.join(':')}';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'youtube',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/channels/$channelId/videos',
        ).replace(queryParameters: params);
        final response = await _client.get(uri);
        _checkResponse(response);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) {
      return const YouTubeSearchResult(videos: [], totalResults: 0);
    }

    return YouTubeSearchResult.fromJson(data);
  }

  // ──── Helpers ────

  void _checkResponse(http.Response response) {
    if (response.statusCode >= 400) {
      throw HttpException(
        'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        statusCode: response.statusCode,
      );
    }
  }
}

class HttpException implements Exception {
  final String message;
  final int statusCode;

  HttpException(this.message, {required this.statusCode});

  @override
  String toString() => 'HttpException($statusCode): $message';
}
