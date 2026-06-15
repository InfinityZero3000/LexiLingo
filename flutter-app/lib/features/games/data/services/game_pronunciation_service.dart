import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lexilingo_app/features/voice/data/datasources/voice_remote_datasource.dart';

/// Audio playback error that can be surfaced to the UI without blocking the game.
class AudioError {
  final String message;
  final bool retryable;

  const AudioError({required this.message, this.retryable = true});

  @override
  String toString() => 'AudioError($message)';
}

/// Thin interface over just_audio's [AudioPlayer] so tests can inject a fake.
abstract class AudioPlayerAdapter {
  Stream<PlayerState> get playerStateStream;
  Future<void> playUrl(String url);
  Future<void> playBytes(Uint8List bytes);
  Future<void> stop();
  Future<void> dispose();
}

/// Default production implementation backed by just_audio.
class JustAudioPlayerAdapter implements AudioPlayerAdapter {
  final AudioPlayer _player;

  JustAudioPlayerAdapter() : _player = AudioPlayer();

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Future<void> playUrl(String url) async {
    await _player.setUrl(url);
    await _player.play();
  }

  @override
  Future<void> playBytes(Uint8List bytes) async {
    await _player.setAudioSource(_BytesAudioSource(bytes));
    await _player.play();
  }

  @override
  Future<void> stop() async => _player.stop();

  @override
  Future<void> dispose() async => _player.dispose();
}

/// Pronunciation service for the Spelling Bee game.
///
/// Priority:
///   1. Play `audio_url` directly if present.
///   2. Synthesize via VoiceRemoteDataSource TTS fallback if no URL.
///
/// Play count is decremented only after audio playback begins successfully.
/// Synthesis failures surface as [AudioError] and do not block the game.
class GamePronunciationService {
  final VoiceRemoteDataSource _voiceDataSource;
  final AudioPlayerAdapter _player;

  GamePronunciationService({
    required VoiceRemoteDataSource voiceDataSource,
    AudioPlayerAdapter? player,
  })  : _voiceDataSource = voiceDataSource,
        _player = player ?? JustAudioPlayerAdapter();

  bool _isPlaying = false;
  AudioError? _lastError;

  bool get isPlaying => _isPlaying;
  AudioError? get lastError => _lastError;

  /// Play pronunciation for [text].
  ///
  /// Returns the new plays-remaining count (i.e. [playsLeft] - 1) on success,
  /// or [playsLeft] unchanged on failure (exposes [lastError]).
  Future<int> play({
    required String text,
    required int playsLeft,
    String? audioUrl,
    required VoidCallback onPlayingChanged,
  }) async {
    if (playsLeft <= 0 || _isPlaying) return playsLeft;

    _isPlaying = true;
    _lastError = null;
    onPlayingChanged();

    try {
      if (audioUrl != null && audioUrl.isNotEmpty) {
        return await _playFromUrl(audioUrl, playsLeft);
      } else {
        return await _playFromTts(text, playsLeft);
      }
    } catch (e) {
      _lastError = AudioError(message: e.toString());
      return playsLeft;
    } finally {
      _isPlaying = false;
      onPlayingChanged();
    }
  }

  Future<int> _playFromUrl(String url, int playsLeft) async {
    // Start playing — the adapter handles setUrl + play atomically.
    // We monitor the stream to know when audio actually starts before
    // decrementing so the count only drops on confirmed playback.
    final startFuture = _player.playerStateStream
        .firstWhere((state) => state.playing)
        .timeout(const Duration(seconds: 5));

    await _player.playUrl(url);
    await startFuture;
    return playsLeft - 1;
  }

  Future<int> _playFromTts(String text, int playsLeft) async {
    final Uint8List audioBytes =
        await _voiceDataSource.synthesizeSpeech(text: text);

    final startFuture = _player.playerStateStream
        .firstWhere((state) => state.playing)
        .timeout(const Duration(seconds: 5));

    await _player.playBytes(audioBytes);
    await startFuture;
    return playsLeft - 1;
  }

  void clearError() {
    _lastError = null;
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

/// [StreamAudioSource] implementation that serves in-memory audio bytes.
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;

  _BytesAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(_bytes.sublist(s, e)),
      contentType: 'audio/mpeg',
    );
  }
}
