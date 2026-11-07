import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_client.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_phase.dart';
import 'package:record/record.dart';

class _Auth implements BackendAuthHeaderProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Recorder implements AudioRecorder {
  @override
  Future<void> dispose() async {}

  @override
  Future<String?> stop() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnavailableRecorder extends _Recorder {
  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async => false;
}

void main() {
  test('start payload separates spoken and native languages', () {
    final payload = buildDuplexStartMessage(
      sessionId: 'voice-1',
      learnerLevel: 'B1',
      nativeLanguage: 'vi',
    );

    expect(payload['language'], 'auto');
    expect(payload['native_language'], 'vi');
  });

  test('exposes the duplex UI contract with safe initial state', () async {
    final client = DuplexVoiceClient(
      authHeaders: _Auth(),
      recorder: _Recorder(),
    );
    addTearDown(client.dispose);

    expect(client.phase.value, DuplexVoicePhase.idle);
    expect(client.inputLevel.value, 0);
    expect(client.lastErrorCode, isNull);
    expect(client.canReplay, isFalse);

    await client.interrupt();
    await client.replayLast();
    expect(client.phase.value, DuplexVoicePhase.idle);
  });

  test('microphone capability failure becomes a retryable UI error', () async {
    final client = DuplexVoiceClient(
      authHeaders: _Auth(),
      recorder: _UnavailableRecorder(),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.start(sessionId: 'session-1'),
      throwsA(isA<StateError>()),
    );

    expect(client.phase.value, DuplexVoicePhase.error);
    expect(client.lastErrorCode, 'MIC_PERMISSION');
  });

  test('packs deployed microphone header', () {
    final frame = packMicrophoneFrame(
      sequence: 7,
      clientTimestampMs: 1234,
      pcm: Uint8List.fromList([1, 2]),
    );
    final header = ByteData.sublistView(frame);
    expect(header.getUint8(0), 1);
    expect(header.getUint32(2, Endian.big), 7);
    expect(header.getUint64(6, Endian.big), 1234);
    expect(frame.sublist(14), [1, 2]);
  });

  test('writes the timestamp as two words so it also works on the web', () {
    for (final ms in [0, 1234, 0xFFFFFFFF, 0x100000000, 0x1FFFFFFFFFFFF]) {
      final frame = packMicrophoneFrame(
        sequence: 1,
        clientTimestampMs: ms,
        pcm: Uint8List.fromList([1, 2]),
      );
      final header = ByteData.sublistView(frame);
      final high = header.getUint32(6, Endian.big);
      final low = header.getUint32(10, Endian.big);
      expect(high * 0x100000000 + low, ms);
    }
  });

  test('validates and extracts TTS PCM', () {
    final frame = Uint8List(18);
    final header = ByteData.sublistView(frame);
    header.setUint8(0, 1);
    header.setUint8(1, 2);
    header.setUint32(2, 7, Endian.big);
    header.setUint16(6, 3, Endian.big);
    header.setUint32(8, 11, Endian.big);
    header.setUint32(12, 2, Endian.big);
    frame.setRange(16, 18, [3, 4]);
    final unpacked = unpackTtsFrame(frame);
    expect(unpacked.turnSeq, 7);
    expect(unpacked.sentenceSeq, 3);
    expect(unpacked.audioSeq, 11);
    expect(unpacked.pcm, [3, 4]);
    frame[1] = 9;
    expect(() => unpackTtsFrame(frame), throwsFormatException);
  });

  test('rejects mismatched TTS payload length', () {
    final frame = Uint8List(17);
    final header = ByteData.sublistView(frame);
    header.setUint8(0, 1);
    header.setUint8(1, 2);
    header.setUint32(12, 2, Endian.big);
    expect(() => unpackTtsFrame(frame), throwsFormatException);
  });
}
