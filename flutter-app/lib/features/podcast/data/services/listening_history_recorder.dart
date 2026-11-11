import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/podcast_entities.dart';
import '../repositories/podcast_repository.dart';

/// Writes the learner's place in the current episode to [PodcastRepository].
///
/// Lives outside the player screen on purpose: playback carries on after the
/// screen is popped, and the place has to keep being recorded then too.
/// The logic is plain method calls ([onPosition], [onPlaying], [onDuration]);
/// [bind] only wires a handler's streams to them.
class ListeningHistoryRecorder {
  ListeningHistoryRecorder(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Position ticks arrive ~5×/s; storage is touched at most this often.
  static const saveEvery = Duration(seconds: 5);

  /// A jump bigger than this between ticks is a seek, not time spent listening.
  static const _maxListenedStep = Duration(seconds: 3);

  final PodcastRepository _repository;
  final DateTime Function() _now;

  PodcastEpisode? _episode;
  String _podcastTitle = '';
  String _artworkUrl = '';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastSaved = Duration.zero;
  Duration _lastTick = Duration.zero;
  int _listenedMs = 0;
  bool _playing = false;

  Future<void> _queue = Future.value();
  Object? _owner;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Wires [position], [duration] and [playing] to this recorder. Calling it
  /// again with the same [owner] is a no-op, so reopening the player screen
  /// does not stack subscriptions.
  void bind({
    required Object owner,
    required Stream<Duration> position,
    required Stream<Duration?> duration,
    required Stream<bool> playing,
  }) {
    if (identical(_owner, owner)) return;
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..addAll([
        position.listen(onPosition),
        duration.listen((d) {
          if (d != null) onDuration(d);
        }),
        playing.listen(onPlaying),
      ]);
    _owner = owner;
  }

  /// Starts recording [episode]. Tracking the one already being recorded only
  /// refreshes its labels, so reopening the screen mid-playback loses nothing.
  void track({
    required PodcastEpisode episode,
    required String podcastTitle,
    required String artworkUrl,
  }) {
    _podcastTitle = podcastTitle;
    _artworkUrl = artworkUrl;
    if (_episode?.guid == episode.guid) return;

    _episode = episode;
    _position = Duration.zero;
    _lastSaved = Duration.zero;
    _lastTick = Duration.zero;
    _listenedMs = 0;
    _duration = Duration(seconds: episode.durationSeconds);
    final guid = episode.guid;
    _queue = _queue
        .then((_) async {
          final before = await _repository.getListeningHistory(guid);
          // Only carry the total forward if nothing was counted meanwhile.
          if (before != null && _episode?.guid == guid && _listenedMs == 0) {
            _listenedMs = before.totalListenedSeconds * 1000;
          }
        })
        .catchError((Object e) {
          _log(e);
        });
  }

  void onDuration(Duration duration) {
    if (duration > Duration.zero) _duration = duration;
  }

  void onPosition(Duration position) {
    if (_episode == null) return;
    final step = position - _lastTick;
    if (_playing && step > Duration.zero && step <= _maxListenedStep) {
      _listenedMs += step.inMilliseconds;
    }
    _lastTick = position;
    _position = position;
    if (_playing && (position - _lastSaved).abs() >= saveEvery) _save();
  }

  void onPlaying(bool playing) {
    final wasPlaying = _playing;
    _playing = playing;
    if (playing && !wasPlaying) _lastTick = _position;
    if (wasPlaying && !playing) _save();
  }

  void _save() {
    final episode = _episode;
    if (episode == null) return;
    final durationSeconds = _duration.inSeconds > 0
        ? _duration.inSeconds
        : episode.durationSeconds;
    final seconds = _position.inSeconds;
    final completed =
        durationSeconds > 0 &&
        seconds >= durationSeconds * ListeningHistory.completedFraction;
    final stamp = _now();
    _lastSaved = _position;

    final entry = ListeningHistory(
      episodeGuid: episode.guid,
      feedUrl: episode.feedUrl,
      lastPositionSeconds: seconds,
      totalListenedSeconds: _listenedMs ~/ 1000,
      durationSeconds: durationSeconds,
      completed: completed,
      completedAt: completed ? stamp : null,
      updatedAt: stamp,
      episode: episode,
      podcastTitle: _podcastTitle,
      artworkUrl: _artworkUrl,
    );
    _queue = _queue
        .then((_) => _repository.saveListeningHistory(entry))
        .catchError((Object e) {
          _log(e);
        });
  }

  /// Completes once every save queued so far has hit storage.
  Future<void> flush() => _queue;

  void _log(Object e) => debugPrint('ListeningHistoryRecorder: $e');
}
