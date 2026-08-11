import 'dart:typed_data';

final class VoiceAudioNormalizer {
  static const _targetRate = 16000;
  int? _sampleRate;
  int? _channels;
  int _inputIndex = 0;
  double _nextOutputPosition = 0;
  int? _previousSample;

  Uint8List normalize(
    Uint8List pcm16le, {
    required int sampleRate,
    required int channels,
  }) {
    if (sampleRate <= 0 ||
        channels <= 0 ||
        pcm16le.length.isOdd ||
        pcm16le.length % (channels * 2) != 0) {
      throw ArgumentError('PCM must contain complete PCM16LE channel frames');
    }
    if (_sampleRate != sampleRate || _channels != channels) {
      reset();
      _sampleRate = sampleRate;
      _channels = channels;
    }

    final input = ByteData.sublistView(pcm16le);
    final mono = <int>[];
    for (var offset = 0; offset < pcm16le.length; offset += channels * 2) {
      var sum = 0;
      for (var channel = 0; channel < channels; channel++) {
        sum += input.getInt16(offset + channel * 2, Endian.little);
      }
      mono.add((sum / channels).truncate().clamp(-32768, 32767));
    }
    if (mono.isEmpty) return Uint8List(0);

    final output = <int>[];
    final step = sampleRate / _targetRate;
    for (final current in mono) {
      if (_previousSample == null) {
        _previousSample = current;
        if (_nextOutputPosition == _inputIndex) {
          output.add(current);
          _nextOutputPosition += step;
        }
        _inputIndex++;
        continue;
      }
      final currentPosition = _inputIndex.toDouble();
      while (_nextOutputPosition <= currentPosition) {
        final fraction = _nextOutputPosition - (currentPosition - 1);
        final interpolated =
            _previousSample! +
            (current - _previousSample!) * fraction.clamp(0.0, 1.0);
        output.add(interpolated.round().clamp(-32768, 32767));
        _nextOutputPosition += step;
      }
      _previousSample = current;
      _inputIndex++;
    }

    final result = ByteData(output.length * 2);
    for (var i = 0; i < output.length; i++) {
      result.setInt16(i * 2, output[i], Endian.little);
    }
    return result.buffer.asUint8List();
  }

  void reset() {
    _sampleRate = null;
    _channels = null;
    _inputIndex = 0;
    _nextOutputPosition = 0;
    _previousSample = null;
  }
}
