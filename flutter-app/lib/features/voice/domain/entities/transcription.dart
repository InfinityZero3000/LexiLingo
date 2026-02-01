import 'package:equatable/equatable.dart';

/// Transcription result entity
/// Represents the result of speech-to-text conversion
class Transcription extends Equatable {
  final String text;
  final String? language;
  final double? confidence;
  final Duration? duration;

  const Transcription({
    required this.text,
    this.language,
    this.confidence,
    this.duration,
  });

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  @override
  List<Object?> get props => [text, language, confidence, duration];
}
