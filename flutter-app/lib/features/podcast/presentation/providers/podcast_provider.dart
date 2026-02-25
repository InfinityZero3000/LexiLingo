import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/repositories/podcast_repository.dart';
import '../../domain/entities/podcast_entities.dart';

/// State management for Podcast feature.
///
/// Phase 4: Podcast.
class PodcastProvider extends ChangeNotifier {
  final PodcastRepository _repository;

  PodcastProvider({PodcastRepository? repository})
    : _repository = repository ?? PodcastRepository();

  // ── State ──

  List<PodcastCategory> _curatedCategories = [];
  List<Podcast> _searchResults = [];
  Podcast? _currentPodcast;
  List<PodcastEpisode> _currentEpisodes = [];
  List<UserPodcastFollow> _followedPodcasts = [];

  bool _isLoading = false;
  bool _isSearching = false;
  String? _error;

  // Playback state
  PodcastEpisode? _currentPlayingEpisode;
  int _playbackPosition = 0; // seconds
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;

  // Debounce timer for search
  Timer? _searchDebounce;

  // ── Getters ──

  List<PodcastCategory> get curatedCategories => _curatedCategories;
  List<Podcast> get searchResults => _searchResults;
  Podcast? get currentPodcast => _currentPodcast;
  List<PodcastEpisode> get currentEpisodes => _currentEpisodes;
  List<UserPodcastFollow> get followedPodcasts => _followedPodcasts;

  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get error => _error;

  PodcastEpisode? get currentPlayingEpisode => _currentPlayingEpisode;
  int get playbackPosition => _playbackPosition;
  bool get isPlaying => _isPlaying;
  double get playbackSpeed => _playbackSpeed;

  // ── Actions ──

  /// Load and cache curated podcast categories from the backend.
  Future<void> loadCuratedPodcasts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _curatedCategories = await _repository.getCuratedPodcasts();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search for podcasts matching [query] with a 300 ms debounce.
  ///
  /// Clears results immediately when [query] is shorter than 2 characters.
  void searchPodcasts(String query) {
    _searchDebounce?.cancel();

    if (query.length < 2) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      _isSearching = true;
      _error = null;
      notifyListeners();

      try {
        _searchResults = await _repository.searchPodcasts(query: query);
      } catch (e) {
        _error = e.toString();
        _searchResults = [];
      } finally {
        _isSearching = false;
        notifyListeners();
      }
    });
  }

  /// Set [podcast] as the active podcast and load its episode list.
  Future<void> loadEpisodes(Podcast podcast) async {
    _currentPodcast = podcast;
    _currentEpisodes = [];
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentEpisodes = await _repository.getEpisodes(
        feedUrl: podcast.feedUrl,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load the user's followed podcasts from local SharedPreferences.
  Future<void> loadFollowedPodcasts() async {
    try {
      _followedPodcasts = await _repository.getFollowedPodcasts();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load followed podcasts: $e');
    }
  }

  /// Follow a podcast if not already following, or unfollow if already following.
  ///
  /// Refreshes [followedPodcasts] after the operation completes.
  Future<void> toggleFollow(Podcast podcast) async {
    final following = await _repository.isFollowing(podcast.feedUrl);
    try {
      if (following) {
        await _repository.unfollowPodcast(podcast.feedUrl);
      } else {
        await _repository.followPodcast(podcast);
      }
      await loadFollowedPodcasts();
    } catch (e) {
      debugPrint('Failed to toggle follow for ${podcast.feedUrl}: $e');
    }
  }

  /// Check whether the user is currently following a podcast by [feedUrl].
  Future<bool> isFollowing(String feedUrl) {
    return _repository.isFollowing(feedUrl);
  }

  /// Update playback state for the currently playing episode.
  ///
  /// Provide only the fields that have changed — omitted fields are unchanged.
  void updatePlaybackState({
    PodcastEpisode? episode,
    int? position,
    bool? isPlaying,
    double? speed,
  }) {
    if (episode != null) _currentPlayingEpisode = episode;
    if (position != null) _playbackPosition = position;
    if (isPlaying != null) _isPlaying = isPlaying;
    if (speed != null) _playbackSpeed = speed;
    notifyListeners();
  }

  /// Clear search results and cancel any pending debounce timer.
  void clearSearch() {
    _searchDebounce?.cancel();
    _searchResults = [];
    notifyListeners();
  }

  /// Download [episode] audio to local storage.
  ///
  /// Marks the episode as [DownloadState.downloading] immediately so the UI
  /// can show a progress indicator. On success the episode entry in
  /// [currentEpisodes] is updated to [DownloadState.downloaded] with the
  /// resolved [localPath].
  ///
  /// Errors are swallowed and the episode is reset to
  /// [DownloadState.notDownloaded] so the user can retry.
  ///
  /// Phase 4: Podcast — skill: performance-offline-fallback.
  Future<void> downloadEpisode(PodcastEpisode episode) async {
    _patchEpisode(episode.copyWith(downloadState: DownloadState.downloading));

    try {
      final updated = await _repository.downloadEpisode(episode);
      _patchEpisode(updated);
    } catch (e) {
      debugPrint('PodcastProvider.downloadEpisode: $e');
      _patchEpisode(
        episode.copyWith(downloadState: DownloadState.notDownloaded),
      );
    }
  }

  /// Replace the matching episode (by [guid]) in [_currentEpisodes] and
  /// notify listeners.
  void _patchEpisode(PodcastEpisode updated) {
    _currentEpisodes = [
      for (final ep in _currentEpisodes)
        if (ep.guid == updated.guid) updated else ep,
    ];
    notifyListeners();
  }

  /// Clear the current error message.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
