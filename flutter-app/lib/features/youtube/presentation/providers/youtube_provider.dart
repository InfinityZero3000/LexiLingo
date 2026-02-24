import 'package:flutter/foundation.dart';
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

  // ── Getters ──
  List<YouTubeChannel> get channels => _channels;
  List<YouTubeVideo> get searchResults => _searchResults;
  List<CaptionSegment> get captions => _captions;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get isLoadingCaptions => _isLoadingCaptions;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  bool get hasMore => _nextPageToken != null;

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

  /// Load next page of search results.
  Future<void> loadMoreResults() async {
    if (_nextPageToken == null || _isSearching) return;

    _isSearching = true;
    notifyListeners();

    try {
      final result = await _repository.searchVideos(
        query: _searchQuery,
        pageToken: _nextPageToken,
      );
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
  Future<void> loadChannelVideos(String channelId) async {
    _isLoading = true;
    _error = null;
    _searchResults = [];
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

  /// Clear search results.
  void clearSearch() {
    _searchResults = [];
    _searchQuery = '';
    _nextPageToken = null;
    _error = null;
    notifyListeners();
  }

  /// Clear error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
