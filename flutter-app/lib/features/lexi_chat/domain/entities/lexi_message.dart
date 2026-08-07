/// Domain entity for a single message in Lexi chat.
class LexiMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final String? audioBase64;
  final List<LexiCorrection> corrections;
  final List<String> linkedConcepts;
  final LexiSuggestedPractice? suggestedPractice;
  final String? nativeHint;
  final Map<String, dynamic>? scores;
  final String syncStatus; // 'synced' | 'pending_sync'
  final String? clientRequestId;

  const LexiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.audioBase64,
    this.corrections = const [],
    this.linkedConcepts = const [],
    this.suggestedPractice,
    this.nativeHint,
    this.scores,
    this.syncStatus = 'synced',
    this.clientRequestId,
  });

  bool get isUser => role == 'user';
  bool get isLexi => role == 'assistant';
  bool get hasAudio => audioBase64 != null && audioBase64!.isNotEmpty;
  bool get hasCorrections => corrections.isNotEmpty;
  bool get isPendingSync => syncStatus == 'pending_sync';

  LexiMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? timestamp,
    String? audioBase64,
    List<LexiCorrection>? corrections,
    List<String>? linkedConcepts,
    LexiSuggestedPractice? suggestedPractice,
    String? nativeHint,
    Map<String, dynamic>? scores,
    String? syncStatus,
    String? clientRequestId,
  }) {
    return LexiMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      audioBase64: audioBase64 ?? this.audioBase64,
      corrections: corrections ?? this.corrections,
      linkedConcepts: linkedConcepts ?? this.linkedConcepts,
      suggestedPractice: suggestedPractice ?? this.suggestedPractice,
      nativeHint: nativeHint ?? this.nativeHint,
      scores: scores ?? this.scores,
      syncStatus: syncStatus ?? this.syncStatus,
      clientRequestId: clientRequestId ?? this.clientRequestId,
    );
  }
}

/// A one-tap follow-up practice prompt tied to the concept behind the
/// mistake just corrected (not a generic "you're weak at X" suggestion).
class LexiSuggestedPractice {
  final String conceptId;
  final String conceptTitle;
  final String prompt;

  const LexiSuggestedPractice({
    required this.conceptId,
    required this.conceptTitle,
    required this.prompt,
  });
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
