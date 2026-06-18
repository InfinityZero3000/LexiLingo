import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lexilingo_app/features/games/data/services/game_pronunciation_service.dart';
import 'package:lexilingo_app/features/voice/data/datasources/voice_remote_datasource.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeVoiceDataSource implements VoiceRemoteDataSource {
  int synthesizeCalls = 0;
  Object? synthesizeError;
  Uint8List synthesizeResult = Uint8List.fromList([0x00, 0x01]);

  @override
  Future<Map<String, dynamic>> transcribeAudio({
    required Uint8List audioData,
    required String filename,
    String? language,
  }) async =>
      {};

  @override
  Future<Uint8List> synthesizeSpeech({required String text}) async {
    synthesizeCalls++;
    if (synthesizeError != null) throw synthesizeError!;
    return synthesizeResult;
  }
}

/// Fake AudioPlayerAdapter — avoids any platform channel calls.
class _FakeAudioPlayerAdapter implements AudioPlayerAdapter {
  int playUrlCalls = 0;
  int playBytesCalls = 0;

  /// When true, the state stream emits a playing event after each play call.
  bool simulatePlayStart;

  Object? playError;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  _FakeAudioPlayerAdapter({this.simulatePlayStart = true});

  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;

  @override
  Future<void> playUrl(String url) async {
    playUrlCalls++;
    if (playError != null) throw playError!;
    if (simulatePlayStart) {
      _stateController.add(PlayerState(true, ProcessingState.ready));
    }
  }

  @override
  Future<void> playBytes(Uint8List bytes) async {
    playBytesCalls++;
    if (playError != null) throw playError!;
    if (simulatePlayStart) {
      _stateController.add(PlayerState(true, ProcessingState.ready));
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('GamePronunciationService', () {
    late _FakeVoiceDataSource fakeVoice;
    late _FakeAudioPlayerAdapter fakePlayer;
    late GamePronunciationService service;

    setUp(() {
      fakeVoice = _FakeVoiceDataSource();
      fakePlayer = _FakeAudioPlayerAdapter();
      service = GamePronunciationService(
        voiceDataSource: fakeVoice,
        player: fakePlayer,
      );
    });

    tearDown(() async {
      await fakePlayer.dispose();
    });

    test('plays from backend audio URL when audio_url is present', () async {
      int playingChanges = 0;

      final newPlaysLeft = await service.play(
        text: 'apple',
        playsLeft: 3,
        audioUrl: 'https://example.com/apple.mp3',
        onPlayingChanged: () => playingChanges++,
      );

      expect(fakePlayer.playUrlCalls, 1);
      expect(fakePlayer.playBytesCalls, 0); // no TTS
      expect(fakeVoice.synthesizeCalls, 0);
      expect(newPlaysLeft, 2); // decremented
      expect(service.lastError, isNull);
      expect(playingChanges, 2); // start + end
    });

    test('falls back to TTS synthesis when no audio_url is provided', () async {
      final newPlaysLeft = await service.play(
        text: 'apple',
        playsLeft: 3,
        audioUrl: null,
        onPlayingChanged: () {},
      );

      expect(fakeVoice.synthesizeCalls, 1);
      expect(fakePlayer.playBytesCalls, 1);
      expect(fakePlayer.playUrlCalls, 0);
      expect(newPlaysLeft, 2);
      expect(service.lastError, isNull);
    });

    test('falls back to TTS when audio_url is empty string', () async {
      final newPlaysLeft = await service.play(
        text: 'apple',
        playsLeft: 2,
        audioUrl: '',
        onPlayingChanged: () {},
      );

      expect(fakeVoice.synthesizeCalls, 1);
      expect(newPlaysLeft, 1);
    });

    test('synthesis failure exposes AudioError without blocking game', () async {
      fakeVoice.synthesizeError = Exception('TTS offline');

      final newPlaysLeft = await service.play(
        text: 'apple',
        playsLeft: 3,
        audioUrl: null,
        onPlayingChanged: () {},
      );

      // Play count unchanged on failure
      expect(newPlaysLeft, 3);
      expect(service.lastError, isNotNull);
      expect(service.lastError!.retryable, isTrue);
      expect(service.lastError!.message, contains('TTS offline'));
    });

    test('play count does not decrement when playback start times out',
        () async {
      // Player does not emit playing state, so the timeout fires first
      fakePlayer = _FakeAudioPlayerAdapter(simulatePlayStart: false);
      service = GamePronunciationService(
        voiceDataSource: fakeVoice,
        player: fakePlayer,
      );

      int result = 3;
      // The service's internal timeout is 5 s; we give it 6 s here
      try {
        result = await service
            .play(
              text: 'apple',
              playsLeft: 3,
              audioUrl: 'https://example.com/apple.mp3',
              onPlayingChanged: () {},
            )
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        // timeout exception — play count should not have changed
      }

      // Either a timeout-based AudioError was set or count stayed at 3
      expect(result, 3);
    });

    test('does not play when playsLeft is 0', () async {
      final newPlaysLeft = await service.play(
        text: 'apple',
        playsLeft: 0,
        audioUrl: 'https://example.com/apple.mp3',
        onPlayingChanged: () {},
      );

      expect(fakePlayer.playUrlCalls, 0);
      expect(newPlaysLeft, 0);
    });

    test('does not start a second play while one is in progress', () async {
      // Disable auto-emit so the first play "hangs"
      fakePlayer = _FakeAudioPlayerAdapter(simulatePlayStart: false);
      service = GamePronunciationService(
        voiceDataSource: fakeVoice,
        player: fakePlayer,
      );

      bool firstStarted = false;
      // Fire first play in background without awaiting
      final firstFuture = service.play(
        text: 'apple',
        playsLeft: 3,
        audioUrl: 'https://example.com/apple.mp3',
        onPlayingChanged: () {
          firstStarted = true;
        },
      );

      // Give the first play time to set isPlaying = true
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(firstStarted, isTrue);
      expect(service.isPlaying, isTrue);

      // Second play should return immediately without calling the adapter
      final secondResult = await service.play(
        text: 'apple',
        playsLeft: 3,
        audioUrl: 'https://example.com/apple.mp3',
        onPlayingChanged: () {},
      );

      expect(secondResult, 3); // not decremented
      expect(fakePlayer.playUrlCalls, 1); // only one adapter call

      // Cancel the hanging first play by closing the controller
      await fakePlayer.dispose();
      await firstFuture.catchError((_) => 3); // swallow timeout/close error
    });

    test('clearError resets lastError', () async {
      fakeVoice.synthesizeError = Exception('fail');
      await service.play(
        text: 'apple',
        playsLeft: 1,
        audioUrl: null,
        onPlayingChanged: () {},
      );
      expect(service.lastError, isNotNull);

      service.clearError();
      expect(service.lastError, isNull);
    });

    test('isPlaying is false after successful play completes', () async {
      await service.play(
        text: 'apple',
        playsLeft: 3,
        audioUrl: 'https://example.com/apple.mp3',
        onPlayingChanged: () {},
      );
      expect(service.isPlaying, isFalse);
    });

    test('isPlaying is false after failed play', () async {
      fakeVoice.synthesizeError = Exception('fail');
      await service.play(
        text: 'apple',
        playsLeft: 3,
        audioUrl: null,
        onPlayingChanged: () {},
      );
      expect(service.isPlaying, isFalse);
    });
  });
}
