import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/services/local_cache_service.dart';
import '../../domain/entities/podcast_entities.dart';

/// Repository for Podcast feature — handles API calls, local SQLite cache,
/// and follow state persisted to SharedPreferences.
///
/// All network calls go through the backend proxy which manages RSS parsing,
/// quota limits, and server-side caching.
///
/// Phase 4: Podcast.
class PodcastRepository {
  final http.Client _client;
  final LocalCacheService _cache;

  static const String _followsKey = 'podcast_follows';

  PodcastRepository({http.Client? client, LocalCacheService? cache})
    : _client = client ?? http.Client(),
      _cache = cache ?? LocalCacheService.instance;

  String get _baseUrl => '${ApiConfig.baseUrl}/podcasts';

  // ──── Search ────

  /// Search for podcasts by query string.
  Future<List<Podcast>> searchPodcasts({
    required String query,
    int maxResults = 10,
  }) async {
    final params = {'q': query, 'max_results': maxResults.toString()};
    final cacheKey =
        'podcast:search:${params.entries.map((e) => '${e.key}:${e.value}').join(':')}';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'podcast',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/search',
        ).replace(queryParameters: params);
        final response = await _client.get(uri);
        _checkResponse(response, uri);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return [];

    return (data['podcasts'] as List<dynamic>? ?? [])
        .map((p) => Podcast.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  // ──── Curated Podcasts ────

  /// Get curated podcast category list from the backend.
  Future<List<PodcastCategory>> getCuratedPodcasts() async {
    const cacheKey = 'podcast:curated';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'podcast',
      fetchFn: () async {
        final uri = Uri.parse('$_baseUrl/curated');
        final response = await _client.get(uri);
        _checkResponse(response, uri);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return [];

    final allPodcasts = (data['podcasts'] as List<dynamic>? ?? [])
        .map((p) => Podcast.fromJson(p as Map<String, dynamic>))
        .toList();
    final podcastById = {for (final p in allPodcasts) p.id: p};

    final categories = (data['categories'] as List<dynamic>? ?? [])
        .map((c) => c as Map<String, dynamic>)
        .map((categoryJson) {
          final podcastIds =
              (categoryJson['podcast_ids'] as List<dynamic>? ?? [])
                  .map((id) => id.toString())
                  .toList();
          final podcasts = podcastIds
              .map((id) => podcastById[id])
              .whereType<Podcast>()
              .toList();

          final id = categoryJson['id'] as String? ?? '';
          final inferredLevel = switch (id) {
            'A1-A2' => 'A1-A2',
            'B1-B2' => 'B1-B2',
            'C1-C2' => 'C1-C2',
            _ => 'B1',
          };

          return PodcastCategory(
            id: id,
            label: categoryJson['label'] as String? ?? '',
            cefrLevel: categoryJson['cefr_level'] as String? ?? inferredLevel,
            podcasts: podcasts,
          );
        })
        .toList();

    return categories;
  }

  // ──── Episodes ────

  /// Get the episode list for a podcast identified by [feedUrl].
  Future<List<PodcastEpisode>> getEpisodes({
    required String feedUrl,
    int limit = 20,
  }) async {
    final params = {'feed_url': feedUrl, 'limit': limit.toString()};
    final cacheKey = 'podcast:episodes:$feedUrl:$limit';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'podcast',
      fetchFn: () async {
        final uri = Uri.parse(
          '$_baseUrl/episodes',
        ).replace(queryParameters: params);
        final response = await _client.get(uri);
        _checkResponse(response, uri);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    if (data == null) return [];

    return (data['episodes'] as List<dynamic>? ?? [])
        .map((e) => PodcastEpisode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Generate or load a cached learner transcript for [episode].
  Future<String?> generateTranscript(PodcastEpisode episode) async {
    final cacheKey = 'podcast:transcript:${episode.guid}';

    final data = await _cache.getOrFetch(
      key: cacheKey,
      type: 'podcast',
      fetchFn: () async {
        final uri = Uri.parse('$_baseUrl/transcript');
        final response = await _client.post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'feed_url': episode.feedUrl,
            'episode_guid': episode.guid,
            'audio_url': episode.audioUrl,
          }),
        );
        _checkResponse(response, uri);
        return jsonDecode(response.body) as Map<String, dynamic>;
      },
    );

    final transcript = data?['transcript'] as String?;
    if (transcript == null || transcript.trim().isEmpty) return null;
    return transcript.trim();
  }

  // ──── Listening History (SQLite via LocalCacheService) ────

  /// Get listening history for a specific episode from local SQLite cache.
  ///
  /// Returns null if no history has been recorded yet.
  Future<ListeningHistory?> getListeningHistory(String episodeGuid) async {
    final key = 'podcast:history:$episodeGuid';
    final raw = await _cache.get(key);
    if (raw == null) return null;
    return ListeningHistory.fromJson(raw as Map<String, dynamic>);
  }

  /// Save or update listening history for an episode in local SQLite cache.
  Future<void> saveListeningHistory(ListeningHistory history) async {
    final key = 'podcast:history:${history.episodeGuid}';
    await _cache.put(key, 'podcast', history.toJson());
  }

  // ──── Followed Podcasts (SharedPreferences) ────

  /// Get all podcasts the user is following from local SharedPreferences.
  Future<List<UserPodcastFollow>> getFollowedPodcasts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_followsKey) ?? [];
    return raw
        .map(
          (s) =>
              UserPodcastFollow.fromJson(jsonDecode(s) as Map<String, dynamic>),
        )
        .toList();
  }

  /// Save a followed podcast to local SharedPreferences.
  ///
  /// Silently ignores duplicates (matched by [feedUrl]).
  Future<void> followPodcast(Podcast podcast) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_followsKey) ?? [];

    final alreadyFollowed = existing.any((s) {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return decoded['feed_url'] == podcast.feedUrl;
    });
    if (alreadyFollowed) return;

    final follow = UserPodcastFollow(
      feedUrl: podcast.feedUrl,
      podcastTitle: podcast.title,
      artworkUrl: podcast.artworkUrl,
      followedAt: DateTime.now(),
    );

    existing.add(jsonEncode(follow.toJson()));
    await prefs.setStringList(_followsKey, existing);
  }

  /// Remove a followed podcast from local SharedPreferences.
  Future<void> unfollowPodcast(String feedUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_followsKey) ?? [];

    final updated = existing.where((s) {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return decoded['feed_url'] != feedUrl;
    }).toList();

    await prefs.setStringList(_followsKey, updated);
  }

  /// Check whether the user is currently following a podcast.
  Future<bool> isFollowing(String feedUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_followsKey) ?? [];
    return existing.any((s) {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return decoded['feed_url'] == feedUrl;
    });
  }

  // ──── Offline Download (skill: performance-offline-fallback) ────

  /// Stream-download [episode] audio to local app storage.
  ///
  /// Saves to `<appDocDir>/podcasts/<guid>.mp3` and persists the path in
  /// SharedPreferences so it survives app restarts.
  ///
  /// Returns the updated [PodcastEpisode] with [DownloadState.downloaded]
  /// and the resolved [localPath].
  ///
  /// Throws if the HTTP request fails or the file cannot be written.
  Future<PodcastEpisode> downloadEpisode(PodcastEpisode episode) async {
    final appDir = await getApplicationDocumentsDirectory();
    final podcastsDir = Directory('${appDir.path}/podcasts');
    if (!podcastsDir.existsSync()) {
      podcastsDir.createSync(recursive: true);
    }

    final filePath = '${podcastsDir.path}/${episode.guid}.mp3';

    // Streaming download to avoid holding the entire file in memory
    final request = http.Request('GET', Uri.parse(episode.audioUrl));
    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode >= 400) {
      throw Exception('Download failed: HTTP ${streamedResponse.statusCode}');
    }

    final file = File(filePath);
    final sink = file.openWrite();
    await streamedResponse.stream.pipe(sink);
    await sink.flush();
    await sink.close();

    await _saveLocalPath(episode.guid, filePath);

    return episode.copyWith(
      downloadState: DownloadState.downloaded,
      localPath: filePath,
    );
  }

  /// Return the local file path for a previously downloaded episode, or
  /// `null` if [guid] has not been downloaded.
  Future<String?> getLocalPath(String guid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('podcast:local:$guid');
  }

  /// Delete the local file for [guid] and remove the persisted path.
  Future<void> deleteDownload(String guid) async {
    final path = await getLocalPath(guid);
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('podcast:local:$guid');
  }

  Future<void> _saveLocalPath(String guid, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('podcast:local:$guid', path);
  }

  // ──── Helpers ────

  void _checkResponse(http.Response response, Uri uri) {
    if (response.statusCode >= 400) {
      final bodyPreview = response.body.length > 400
          ? '${response.body.substring(0, 400)}...'
          : response.body;
      debugPrint(
        '[PodcastRepository] HTTP ${response.statusCode} ${response.reasonPhrase} '
        'for $uri\nResponse: $bodyPreview',
      );
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }
  }
}
