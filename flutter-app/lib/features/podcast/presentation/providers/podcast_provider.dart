import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/repositories/podcast_repository.dart';
import '../../domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/core/state/reset_epoch.dart';

/// State management for Podcast feature.
///
/// Phase 4: Podcast.
class PodcastProvider extends ChangeNotifier with ResetEpoch {
  final PodcastRepository _repository;

  PodcastProvider({PodcastRepository? repository})
    : _repository = repository ?? PodcastRepository();

  // ── State ──

  List<PodcastCategory> _curatedCategories = [];
  List<Podcast> _searchResults = [];
  Podcast? _currentPodcast;
  List<PodcastEpisode> _currentEpisodes = [];
  List<UserPodcastFollow> _followedPodcasts = [];
  List<ListeningHistory> _continueListening = [];

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
  List<ListeningHistory> get continueListening => _continueListening;

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
    final epoch = resetEpoch;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final curated = await _repository.getCuratedPodcasts();
      if (isStale(epoch)) return;
      _curatedCategories = curated;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  int _searchToken = 0;
  int _episodesToken = 0;

  /// Search for podcasts matching [query] with a 300 ms debounce.
  ///
  /// Clears results immediately when [query] is shorter than 2 characters.
  void searchPodcasts(String query) {
    _searchDebounce?.cancel();

    if (query.length < 2) {
      _searchToken++;
      _isSearching = false;
      _searchResults = [];
      notifyListeners();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final token = ++_searchToken;
      _isSearching = true;
      _error = null;
      notifyListeners();

      try {
        final results = await _repository.searchPodcasts(query: query);
        if (token != _searchToken) return;
        _searchResults = results;
      } catch (e) {
        if (token != _searchToken) return;
        _error = e.toString();
        _searchResults = [];
      } finally {
        if (token == _searchToken) {
          _isSearching = false;
          notifyListeners();
        }
      }
    });
  }

  /// Set [podcast] as the active podcast and load its episode list.
  Future<void> loadEpisodes(Podcast podcast) async {
    final token = ++_episodesToken;
    final epoch = resetEpoch;
    _currentPodcast = podcast;
    _currentEpisodes = [];
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final episodes = await _repository.getEpisodes(feedUrl: podcast.feedUrl);
      final withProgress = await _withListeningProgress(episodes);
      if (token != _episodesToken || isStale(epoch)) return;
      _currentEpisodes = withProgress;
    } catch (e) {
      if (token != _episodesToken || isStale(epoch)) return;
      debugPrint(
        '[PodcastProvider] loadEpisodes failed for "${podcast.title}" '
        '(feed: ${podcast.feedUrl}): $e',
      );
      _error = e.toString();
    } finally {
      if (token == _episodesToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Overlays the learner's saved place onto freshly fetched [episodes].
  /// A history failure must never cost the episode list itself.
  Future<List<PodcastEpisode>> _withListeningProgress(
    List<PodcastEpisode> episodes,
  ) async {
    try {
      final byGuid = {
        for (final h in await _repository.getRecentListening())
          h.episodeGuid: h,
      };
      return [
        for (final e in episodes)
          if (byGuid[e.guid] case final h?)
            e.copyWith(
              listenProgress: h.lastPositionSeconds,
              isCompleted: h.completed,
            )
          else
            e,
      ];
    } catch (e) {
      debugPrint('PodcastProvider: listening progress unavailable: $e');
      return episodes;
    }
  }

  /// Refresh the "continue listening" shelf from local history.
  Future<void> loadContinueListening() async {
    final epoch = resetEpoch;
    try {
      final shelf = await _repository.getContinueListening();
      if (isStale(epoch)) return;
      _continueListening = shelf;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load continue listening: $e');
    }
  }

  /// Load the user's followed podcasts from local SharedPreferences.
  Future<void> loadFollowedPodcasts() async {
    final epoch = resetEpoch;
    try {
      final follows = await _repository.getFollowedPodcasts();
      if (isStale(epoch)) return;
      _followedPodcasts = follows;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load followed podcasts: $e');
    }
  }

  /// Follow a podcast if not already following, or unfollow if already following.
  ///
  /// Refreshes [followedPodcasts] after the operation completes.
  Future<void> toggleFollow(Podcast podcast) async {
    final epoch = resetEpoch;
    final following = await _repository.isFollowing(podcast.feedUrl);
    if (isStale(epoch)) return;
    try {
      if (following) {
        await _repository.unfollowPodcast(podcast.feedUrl);
      } else {
        await _repository.followPodcast(podcast);
      }
      if (isStale(epoch)) return;
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
    final epoch = resetEpoch;
    _patchEpisode(episode.copyWith(downloadState: DownloadState.downloading));

    try {
      final updated = await _repository.downloadEpisode(episode);
      if (isStale(epoch)) return;
      _patchEpisode(updated);
    } catch (e) {
      if (isStale(epoch)) return;
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

  void reset() {
    bumpResetEpoch();
    _searchToken++;
    _episodesToken++;
    _searchDebounce?.cancel();
    _searchResults = [];
    _currentPodcast = null;
    _currentEpisodes = [];
    _followedPodcasts = [];
    _continueListening = [];
    _curatedCategories = [];
    _isLoading = false;
    _isSearching = false;
    _error = null;
    _currentPlayingEpisode = null;
    _playbackPosition = 0;
    _isPlaying = false;
    _playbackSpeed = 1.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
