/// Domain entity for a single message in Lexi chat.
class LexiMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final String? audioBase64;
  final List<LexiCorrection> corrections;
  final List<String> linkedConcepts;
  final String? vietnameseHint;
  final Map<String, dynamic>? scores;

  const LexiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.audioBase64,
    this.corrections = const [],
    this.linkedConcepts = const [],
    this.vietnameseHint,
    this.scores,
  });

  bool get isUser => role == 'user';
  bool get isLexi => role == 'assistant';
  bool get hasAudio => audioBase64 != null && audioBase64!.isNotEmpty;
  bool get hasCorrections => corrections.isNotEmpty;
}

/// A grammar/vocabulary correction from Lexi.
class LexiCorrection {
  final String errorSpan;
  final String correction;
  final String errorType;
  final String explanation;

  const LexiCorrection({
    required this.errorSpan,
    required this.correction,
    required this.errorType,
    required this.explanation,
  });
}
