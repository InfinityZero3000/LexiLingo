import 'topic_session.dart';

/// SSE events for streaming topic/story chat — mirrors [LexiStreamEvent]'s
/// shape (see lexi_chat feature) but carries only what topic chat needs:
/// no audio/corrections/vietnamese_hint, since the backend response for
/// this feature never has them.
sealed class TopicStreamEvent {
  const TopicStreamEvent();
}

/// Sent immediately: the AI pipeline has started processing.
class TopicStreamThinking extends TopicStreamEvent {
  const TopicStreamThinking();
}

/// One word from the AI response — shows typewriter effect.
class TopicStreamChunk extends TopicStreamEvent {
  final String text;
  const TopicStreamChunk(this.text);
}

/// Final event: full response with hints/metadata, same shape as the
/// non-streaming endpoint's [TopicChatResponse].
class TopicStreamDone extends TopicStreamEvent {
  final TopicChatResponse response;
  const TopicStreamDone(this.response);
}

/// Sent if the pipeline fails unrecoverably (session/quota/service down).
class TopicStreamError extends TopicStreamEvent {
  final String error;
  const TopicStreamError(this.error);
}
