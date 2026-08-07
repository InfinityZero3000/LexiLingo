import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';

sealed class LexiStreamEvent {
  const LexiStreamEvent();
}

/// Sent immediately: the AI pipeline has started processing.
class LexiStreamThinking extends LexiStreamEvent {
  const LexiStreamThinking();
}

/// One word (or token) from the AI response — shows typewriter effect.
class LexiStreamChunk extends LexiStreamEvent {
  final String text;
  const LexiStreamChunk(this.text);
}

/// Final event: full message with corrections, audio, etc.
class LexiStreamDone extends LexiStreamEvent {
  final String messageId;
  final String sessionId;

  /// Full response text — fallback when chunk accumulation is empty.
  final String? fullText;
  final List<LexiCorrection> corrections;
  final List<String> linkedConcepts;
  final LexiSuggestedPractice? suggestedPractice;
  final String? nativeHint;
  final Map<String, dynamic>? scores;
  final String? audioBase64;
  final String? storyContext;
  final Map<String, dynamic> metadata;

  const LexiStreamDone({
    required this.messageId,
    required this.sessionId,
    this.fullText,
    required this.corrections,
    required this.linkedConcepts,
    this.suggestedPractice,
    this.nativeHint,
    this.scores,
    this.audioBase64,
    this.storyContext,
    required this.metadata,
  });
}

/// Sent if the pipeline fails unrecoverably.
class LexiStreamError extends LexiStreamEvent {
  final String error;
  const LexiStreamError(this.error);
}
