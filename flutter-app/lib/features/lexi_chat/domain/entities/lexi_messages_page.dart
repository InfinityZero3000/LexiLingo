import 'lexi_message.dart';

/// Cursor-based page of Lexi chat messages.
class LexiMessagesPage {
  final List<LexiMessage> messages;
  final bool hasMore;
  final String? nextCursor;
  final int returned;

  const LexiMessagesPage({
    required this.messages,
    required this.hasMore,
    required this.nextCursor,
    required this.returned,
  });
}
