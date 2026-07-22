import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/voice/pcm_frame_chunker.dart';
import 'package:lexilingo_app/core/voice/voice_audio_normalizer.dart';
import 'package:record/record.dart';

void main() {
  const enabled = bool.fromEnvironment('VOICE_GATE0_DEVICE');

  testWidgets('captures PCM and immediately plays a released buffer stream', (
    tester,
  ) async {
    // The tap is intentional: browsers require a user gesture before audio init.
    var tapped = false;
    final soloud = SoLoud.instance;
    final audioUnlocked = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () {
              tapped = true;
              soloud.init().then(
                (_) => audioUnlocked.complete(),
                onError: audioUnlocked.completeError,
              );
            },
            child: const Text('Start Gate 0'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start Gate 0'));
    expect(tapped, isTrue);
    await audioUnlocked.future;

    final recorder = AudioRecorder();
    StreamSubscription<Uint8List>? subscription;
    AudioSource? source;
    SoundHandle? handle;
    final stopwatch = Stopwatch();
    var firstPlaybackMs = -1;
    var underruns = 0;
    var hasBuffered = false;
    var nonSilentQueued = false;
    final playbackStarted = Completer<void>();
    const captureSampleRate = 48000;
    const captureChannels = 1;
    try {
      expect(await recorder.isEncoderSupported(AudioEncoder.pcm16bits), isTrue);
      source = soloud.setBufferStream(
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: 0.08,
        sampleRate: 16000,
        channels: Channels.mono,
        format: BufferType.s16le,
        onBuffering: (buffering, _, __) {
          if (buffering) {
            hasBuffered = true;
            underruns++;
          } else if (hasBuffered &&
              nonSilentQueued &&
              !playbackStarted.isCompleted) {
            firstPlaybackMs = stopwatch.elapsedMilliseconds;
            playbackStarted.complete();
          }
        },
      );
      handle = await soloud.play(source);
      final normalizer = VoiceAudioNormalizer();
      final chunker = PcmFrameChunker();
      stopwatch.start();
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: captureSampleRate,
          numChannels: captureChannels,
        ),
      );
      subscription = stream.listen((bytes) {
        final canonical = normalizer.normalize(
          bytes,
          sampleRate: captureSampleRate,
          channels: captureChannels,
        );
        for (final frame in chunker.add(canonical)) {
          if (frame.any((byte) => byte != 0)) {
            nonSilentQueued = true;
          }
          soloud.addAudioDataStream(source!, frame);
        }
      });
      await playbackStarted.future.timeout(const Duration(seconds: 10));
      expect(firstPlaybackMs, greaterThanOrEqualTo(0));
      expect(underruns, lessThan(3));
    } finally {
      await subscription?.cancel();
      await recorder.cancel();
      recorder.dispose();
      if (handle != null) await soloud.stop(handle);
      if (source != null) soloud.disposeSource(source);
      if (soloud.isInitialized) soloud.deinit();
    }
  }, skip: !enabled);
}
