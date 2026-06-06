import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/youtube_repository.dart';
import '../../domain/entities/youtube_entities.dart';

/// State management for YouTube feature.
///
/// Phase 1: YouTube Video Integration.
class YouTubeProvider extends ChangeNotifier {
  final YouTubeRepository _repository;

  YouTubeProvider({YouTubeRepository? repository})
    : _repository = repository ?? YouTubeRepository();

  // ── State ──
  List<YouTubeChannel> _channels = [];
  List<YouTubeVideo> _searchResults = [];
  List<CaptionSegment> _captions = [];
  String? _nextPageToken;
  bool _isLoading = false;
  bool _isSearching = false;
  bool _isLoadingCaptions = false;
  String? _error;
  String _searchQuery = '';
  String _activeChannelName = '';
  String _activeChannelId = '';

  // ── Saved videos (persisted) ──
  // videoId -> SavedVideo (insertion order = save order, newest first via LinkedHashMap)
  final Map<String, SavedVideo> _savedVideos = {};
  static const _prefsSavedKey = 'youtube_saved_videos';

  // ── Watch History (persisted) ──
  final List<YouTubeVideo> _watchHistory = [];
  static const _prefsHistoryKey = 'youtube_watch_history';

  // ── Recommended videos ──
  List<YouTubeVideo> _recommendedVideos = [];
  bool _isLoadingRecommendations = false;

  // ── Translation session state ──
  // Memory cache: "${word}:${lang}" -> WordTranslation (survives video navigation)
  final Map<String, WordTranslation> _translationMemCache = {};
  // Per-video history: videoId -> ordered list of looked-up words (newest first)
  final Map<String, List<WordTranslation>> _videoTranslationHistory = {};

  // ── Getters ──
  List<YouTubeChannel> get channels => _channels;
  List<YouTubeVideo> get searchResults => _searchResults;
  List<CaptionSegment> get captions => _captions;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get isLoadingCaptions => _isLoadingCaptions;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get activeChannelName => _activeChannelName;
  bool get hasMore => _nextPageToken != null;

  /// Saved videos, newest first.
  List<SavedVideo> get savedVideos =>
      _savedVideos.values.toList().reversed.toList();

  /// Watch history, newest first.
  List<YouTubeVideo> get watchHistory => List.unmodifiable(_watchHistory);

  /// Recommended videos.
  List<YouTubeVideo> get recommendedVideos => _recommendedVideos;
  bool get isLoadingRecommendations => _isLoadingRecommendations;

  bool isVideoSaved(String videoId) => _savedVideos.containsKey(videoId);

  /// Returns looked-up words for a specific video (newest first).
  List<WordTranslation> translationHistoryFor(String videoId) =>
      List.unmodifiable(_videoTranslationHistory[videoId] ?? const []);

  // ── Init ──

  /// Load persisted saved videos from SharedPreferences.
  Future<void> loadSavedVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsSavedKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final v = SavedVideo.fromJson(item as Map<String, dynamic>);
          _savedVideos[v.videoId] = v;
        }
      }

      // Also load watch history
      final rawHist = prefs.getString(_prefsHistoryKey);
      if (rawHist != null) {
        final listHist = jsonDecode(rawHist) as List<dynamic>;
        _watchHistory.clear();
        for (final item in listHist) {
          _watchHistory.add(YouTubeVideo.fromJson(item as Map<String, dynamic>));
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Load persisted watch history from SharedPreferences.
  Future<void> loadWatchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsHistoryKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _watchHistory.clear();
      for (final item in list) {
        _watchHistory.add(YouTubeVideo.fromJson(item as Map<String, dynamic>));
      }
      notifyListeners();
    } catch (_) {}
  }

  // ── Actions ──

  /// Load curated channels (no API cost).
  Future<void> loadChannels({String? category}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _channels = await _repository.getCuratedChannels(category: category);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search for videos by query.
  Future<void> searchVideos(String query, {String? channelId}) async {
    if (query.length < 2) return;

    _searchQuery = query;
    _activeChannelName = '';
    _activeChannelId = '';
    _isSearching = true;
    _error = null;
    _searchResults = [];
    _nextPageToken = null;
    notifyListeners();

    try {
      final result = await _repository.searchVideos(
        query: query,
        channelId: channelId,
      );
      _searchResults = result.videos;
      _nextPageToken = result.nextPageToken;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Load next page of search results or channel videos.
  Future<void> loadMoreResults() async {
    if (_nextPageToken == null || _isSearching) return;

    _isSearching = true;
    notifyListeners();

    try {
      final YouTubeSearchResult result;
      if (_activeChannelId.isNotEmpty) {
        // Paginate channel videos using the channel endpoint (not search)
        result = await _repository.getChannelVideos(
          _activeChannelId,
          pageToken: _nextPageToken,
        );
      } else {
        result = await _repository.searchVideos(
          query: _searchQuery,
          pageToken: _nextPageToken,
        );
      }
      _searchResults.addAll(result.videos);
      _nextPageToken = result.nextPageToken;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Load videos from a specific channel.
  /// Sets [_searchQuery] to a non-empty sentinel so the UI switches to
  /// the results view (same as search results) to display the loaded videos.
  Future<void> loadChannelVideos(
    String channelId, {
    String channelName = '',
  }) async {
    _isLoading = true;
    _error = null;
    _searchResults = [];
    // Set query so Consumer switches to _buildSearchResults
    _searchQuery = channelName.isNotEmpty ? channelName : channelId;
    _activeChannelName = channelName;
    _activeChannelId = channelId;
    _nextPageToken = null;
    notifyListeners();

    try {
      final result = await _repository.getChannelVideos(channelId);
      _searchResults = result.videos;
      _nextPageToken = result.nextPageToken;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load captions for a video.
  Future<void> loadCaptions(String videoId, {String lang = 'en'}) async {
    _isLoadingCaptions = true;
    _captions = [];
    notifyListeners();

    try {
      _captions = await _repository.getCaptions(videoId, lang: lang);
    } catch (e) {
      debugPrint('Failed to load captions: $e');
    } finally {
      _isLoadingCaptions = false;
      notifyListeners();
    }
  }

  /// Find the active caption at a given playback position.
  CaptionSegment? getActiveCaptionAt(int positionMs) {
    for (final segment in _captions) {
      if (segment.isActiveAt(positionMs)) return segment;
    }
    return null;
  }

  // ── Save / Unsave Videos ──

  Future<void> saveVideo(YouTubeVideo video) async {
    _savedVideos[video.videoId] = SavedVideo.fromVideo(video);
    notifyListeners();
    await _persistSavedVideos();
  }

  Future<void> unsaveVideo(String videoId) async {
    _savedVideos.remove(videoId);
    notifyListeners();
    await _persistSavedVideos();
  }

  Future<void> _persistSavedVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _savedVideos.values.map((v) => v.toJson()).toList();
      await prefs.setString(_prefsSavedKey, jsonEncode(list));
    } catch (_) {}
  }

  // ── Translation ──

  /// Translate / look up a word.
  ///
  /// Checks in-memory cache first (instant). On cache miss, calls the backend
  /// and stores the result in both the memory cache and the video's history.
  /// Always resolves — never throws.
  Future<WordTranslation> translateWord(
    String word, {
    String lang = 'vi',
    String? videoId,
    String? contextSentence,
  }) async {
    final memKey = '${word.toLowerCase()}:$lang';

    WordTranslation result;

    if (_translationMemCache.containsKey(memKey)) {
      result = _translationMemCache[memKey]!;
    } else {
      result = await _repository.translateWord(word, lang: lang);
      _translationMemCache[memKey] = result;
    }

    if (videoId != null) {
      final withCtx = result.copyWith(contextSentence: contextSentence);
      _addToHistory(videoId, withCtx);
      return withCtx;
    }

    return result;
  }

  void _addToHistory(String videoId, WordTranslation entry) {
    final list = _videoTranslationHistory[videoId] ??= [];
    final idx = list.indexWhere((t) => t.word == entry.word);
    if (idx >= 0) {
      list[idx] = entry; // update context sentence if changed
    } else {
      list.insert(0, entry); // newest first
    }
    notifyListeners();
  }

  // ── Watch History Actions ──

  Future<void> addToHistory(YouTubeVideo video) async {
    _watchHistory.removeWhere((v) => v.videoId == video.videoId);
    _watchHistory.insert(0, video);
    if (_watchHistory.length > 20) {
      _watchHistory.removeLast();
    }
    notifyListeners();
    await _persistWatchHistory();
  }

  Future<void> clearWatchHistory() async {
    _watchHistory.clear();
    notifyListeners();
    await _persistWatchHistory();
  }

  Future<void> _persistWatchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _watchHistory.map((v) => v.toJson()).toList();
      await prefs.setString(_prefsHistoryKey, jsonEncode(list));
    } catch (_) {}
  }

  // ── Recommendations Actions ──

  Future<void> loadRecommendations() async {
    _isLoadingRecommendations = true;
    _error = null;
    notifyListeners();

    try {
      String query = 'Learn English';
      String? channelId;

      if (_watchHistory.isNotEmpty) {
        final recent = _watchHistory.first;
        if (recent.channelId.isNotEmpty) {
          channelId = recent.channelId;
          final words = recent.title.split(' ');
          if (words.isNotEmpty) {
            query = words.take(2).join(' ');
          }
        }
      }

      final result = await _repository.searchVideos(
        query: query.isNotEmpty ? query : 'Learn English',
        channelId: channelId,
        maxResults: 10,
      );
      _recommendedVideos = result.videos;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  // ── Clear ──

  /// Clear search results and return to channels view.
  /// Translation history and memory cache are intentionally preserved so
  /// words looked up during this session survive channel navigation.
  void clearSearch() {
    _searchResults = [];
    _searchQuery = '';
    _activeChannelName = '';
    _activeChannelId = '';
    _nextPageToken = null;
    _error = null;
    notifyListeners();
  }

  /// Clear everything including translation history.
  /// Call this when the user navigates away from the YouTube section entirely.
  void clearAll() {
    _translationMemCache.clear();
    _videoTranslationHistory.clear();
    clearSearch();
  }

  /// Clear error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
