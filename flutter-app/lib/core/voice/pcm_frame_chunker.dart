import 'dart:typed_data';

final class PcmFrameChunker {
  static const frameBytes = 640;
  Uint8List _remainder = Uint8List(0);

  List<Uint8List> add(Uint8List canonicalPcm) {
    if (canonicalPcm.isEmpty) return const [];
    final bytes = Uint8List(_remainder.length + canonicalPcm.length)
      ..setAll(0, _remainder)
      ..setAll(_remainder.length, canonicalPcm);
    final complete = bytes.length ~/ frameBytes;
    final frames = [
      for (var i = 0; i < complete; i++)
        Uint8List.fromList(bytes.sublist(i * frameBytes, (i + 1) * frameBytes)),
    ];
    _remainder = Uint8List.fromList(bytes.sublist(complete * frameBytes));
    return frames;
  }

  void reset() => _remainder = Uint8List(0);
}
