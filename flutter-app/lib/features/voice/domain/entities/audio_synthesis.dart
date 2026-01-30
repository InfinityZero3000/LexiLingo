import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Audio synthesis result entity
/// Represents the result of text-to-speech conversion
class AudioSynthesis extends Equatable {
  final Uint8List audioData;
  final String mimeType;
  final Duration? duration;
  final int? sampleRate;

  const AudioSynthesis({
    required this.audioData,
    this.mimeType = 'audio/wav',
    this.duration,
    this.sampleRate,
  });

  bool get isEmpty => audioData.isEmpty;
  bool get isNotEmpty => audioData.isNotEmpty;
  
  int get sizeInBytes => audioData.length;

  @override
  List<Object?> get props => [audioData, mimeType, duration, sampleRate];
}
