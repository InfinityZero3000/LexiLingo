import 'package:equatable/equatable.dart';
import 'chat_message.dart';

/// Represents a chat conversation session
/// A session contains multiple messages between user and AI
class ChatSession extends Equatable {
  /// Unique identifier for this session
  final String id;

  /// ID of the user who owns this session
  final String userId;

  /// Title/name of the chat session
  final String title;

  /// When this session was created
  final DateTime createdAt;

  /// When the last message was sent in this session
  final DateTime? lastMessageAt;

  /// List of messages in this session (optional, loaded separately)
  final List<ChatMessage>? messages;

  const ChatSession({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    this.lastMessageAt,
    this.messages,
  });

  /// Create a copy with some fields updated
  ChatSession copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    List<ChatMessage>? messages,
  }) {
    return ChatSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messages: messages ?? this.messages,
    );
  }

  /// Get the number of messages in this session
  int get messageCount => messages?.length ?? 0;

  /// Check if this session has any messages
  bool get hasMessages => messageCount > 0;

  /// Get the last message in this session
  ChatMessage? get lastMessage {
    if (messages == null || messages!.isEmpty) return null;
    return messages!.last;
  }

  /// Check if this session is empty (no messages)
  bool get isEmpty => !hasMessages;

  /// Get a preview of the last message (first 50 chars)
  String? get lastMessagePreview {
    final last = lastMessage;
    if (last == null) return null;
    if (last.content.length <= 50) return last.content;
    return '${last.content.substring(0, 50)}...';
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        title,
        createdAt,
        lastMessageAt,
        messages,
      ];

  @override
  String toString() {
    return 'ChatSession(id: $id, title: $title, messageCount: $messageCount)';
  }
}
