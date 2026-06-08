import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';

/// Background audio handler for podcast playback.
///
/// Wraps [AudioPlayer] from `just_audio` and bridges it to `audio_service`
/// so playback continues when the app is in the background and OS media
/// controls (lock screen, notification shade) remain functional.
///
/// Phase 4: Podcast — skill: audio-format-optimization.
class PodcastAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  PodcastAudioHandler() {
    // Forward every playback event to AudioService's playbackState BehaviourSubject
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Keep AudioService's mediaItem duration up-to-date as the stream resolves
    _player.durationStream.listen((duration) {
      final current = mediaItem.value;
      if (current != null && duration != null) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
  }

  // ── Source loading ────────────────────────────────────────────────────────

  /// Load and prepare [episode] for playback.
  ///
  /// Resolves the audio source: prefers a downloaded [localPath] if the file
  /// exists on disk, otherwise streams from the network [audioUrl].
  Future<void> setEpisode(PodcastEpisode episode) async {
    final item = MediaItem(
      id: episode.guid,
      title: episode.title,
      album: '',
      artUri: (episode.imageUrl?.isNotEmpty ?? false)
          ? Uri.tryParse(episode.imageUrl!)
          : null,
    );
    mediaItem.add(item);

    final useLocal = !kIsWeb &&
        episode.localPath != null &&
        File(episode.localPath!).existsSync();

    final AudioSource source;
    if (useLocal) {
      source = AudioSource.file(episode.localPath!, tag: item);
    } else {
      source = AudioSource.uri(Uri.parse(episode.audioUrl), tag: item);
    }

    await _player.setAudioSource(source);
  }

  /// Set playback speed (0.5x – 2.0x).
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  // ── BaseAudioHandler overrides ────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> fastForward() =>
      _player.seek(_player.position + const Duration(seconds: 15));

  @override
  Future<void> rewind() {
    final target = _player.position - const Duration(seconds: 15);
    return _player.seek(target.isNegative ? Duration.zero : target);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  // ── Passthrough getters for the player screen ─────────────────────────────

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  bool get playing => _player.playing;
  Duration get currentPosition => _player.position;

  // ── Internal helpers ──────────────────────────────────────────────────────

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
