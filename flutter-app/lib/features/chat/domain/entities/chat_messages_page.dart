import 'package:equatable/equatable.dart';

import 'chat_message.dart';

/// Represents one page of chat messages fetched via cursor-based pagination.
class ChatMessagesPage extends Equatable {
  final List<ChatMessage> messages;
  final bool hasMore;
  final String? nextCursor;
  final int returned;

  const ChatMessagesPage({
    required this.messages,
    required this.hasMore,
    required this.nextCursor,
    required this.returned,
  });

  @override
  List<Object?> get props => [messages, hasMore, nextCursor, returned];
}
