import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/voice/pcm_frame_chunker.dart';

void main() {
  test('emits exact 20 ms PCM frames and retains the remainder', () {
    final chunker = PcmFrameChunker();
    final output = <Uint8List>[];
    for (final size in [1, 319, 640, 641, 4096]) {
      output.addAll(chunker.add(Uint8List(size)));
    }

    expect(output, hasLength(8));
    expect(output.every((frame) => frame.length == 640), isTrue);
    expect(chunker.add(Uint8List(62)), isEmpty);
    expect(chunker.add(Uint8List(1)), hasLength(1));
  });

  test('preserves little-endian bytes and resets after route change', () {
    final chunker = PcmFrameChunker();
    final bytes = Uint8List.fromList(List.generate(640, (i) => i & 0xff));
    expect(chunker.add(bytes).single, orderedEquals(bytes));
    chunker.add(Uint8List(319));
    chunker.reset();
    expect(chunker.add(Uint8List(321)), isEmpty);
  });

  test('accounts for ten minutes without drift', () {
    final chunker = PcmFrameChunker();
    var emitted = 0;
    const total = 16000 * 2 * 60 * 10;
    for (var offset = 0; offset < total; offset += 4096) {
      final size = (total - offset).clamp(0, 4096);
      emitted += chunker.add(Uint8List(size)).fold(0, (n, f) => n + f.length);
    }
    expect(emitted, total);
  });
}
