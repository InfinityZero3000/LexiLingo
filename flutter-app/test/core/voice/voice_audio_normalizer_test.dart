import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/voice/voice_audio_normalizer.dart';

Uint8List pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < bytes.length; i += 2) data.getInt16(i, Endian.little),
  ];
}

void main() {
  test('keeps 16 kHz mono PCM16LE unchanged', () {
    final normalizer = VoiceAudioNormalizer();
    expect(
      samples(
        normalizer.normalize(
          pcm([-32768, 0, 32767]),
          sampleRate: 16000,
          channels: 1,
        ),
      ),
      [-32768, 0, 32767],
    );
  });

  test('downmixes stereo and clips safely', () {
    final normalizer = VoiceAudioNormalizer();
    expect(
      samples(
        normalizer.normalize(
          pcm([32767, 32767, -32768, -32768]),
          sampleRate: 16000,
          channels: 2,
        ),
      ),
      [32767, -32768],
    );
  });

  for (final rate in [44100, 48000]) {
    test('resamples $rate Hz to 16 kHz across arbitrary chunks', () {
      final input = List<int>.generate(rate, (i) => (i % 200) - 100);
      final whole = VoiceAudioNormalizer().normalize(
        pcm(input),
        sampleRate: rate,
        channels: 1,
      );
      final split = VoiceAudioNormalizer();
      final a = split.normalize(
        pcm(input.sublist(0, 137)),
        sampleRate: rate,
        channels: 1,
      );
      final b = split.normalize(
        pcm(input.sublist(137)),
        sampleRate: rate,
        channels: 1,
      );
      expect([...a, ...b], orderedEquals(whole));
      expect(whole.length, 16000 * 2);
    });
  }

  test('carries fractional phase and resets on explicit or format change', () {
    final normalizer = VoiceAudioNormalizer();
    final first = normalizer.normalize(
      pcm(List.filled(100, 1000)),
      sampleRate: 44100,
      channels: 1,
    );
    final second = normalizer.normalize(
      pcm(List.filled(100, 1000)),
      sampleRate: 44100,
      channels: 1,
    );
    expect(
      first.length + second.length,
      VoiceAudioNormalizer()
          .normalize(
            pcm(List.filled(200, 1000)),
            sampleRate: 44100,
            channels: 1,
          )
          .length,
    );

    normalizer.reset();
    expect(
      normalizer.normalize(pcm([7]), sampleRate: 16000, channels: 1),
      orderedEquals(pcm([7])),
    );
    expect(
      normalizer.normalize(pcm([8]), sampleRate: 48000, channels: 1),
      orderedEquals(pcm([8])),
    );
  });

  test('rejects invalid and incomplete formats', () {
    final normalizer = VoiceAudioNormalizer();
    expect(
      () => normalizer.normalize(Uint8List(1), sampleRate: 16000, channels: 1),
      throwsArgumentError,
    );
    expect(
      () => normalizer.normalize(pcm([1]), sampleRate: 0, channels: 1),
      throwsArgumentError,
    );
    expect(
      () => normalizer.normalize(pcm([1]), sampleRate: 16000, channels: 0),
      throwsArgumentError,
    );
  });
}
