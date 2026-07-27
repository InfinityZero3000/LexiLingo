import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_client.dart';

void main() {
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
