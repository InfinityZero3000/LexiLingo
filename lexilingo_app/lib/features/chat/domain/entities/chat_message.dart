import 'package:equatable/equatable.dart';

/// Represents a single chat message in a conversation
/// This is a domain entity - pure business logic with no dependencies
class ChatMessage extends Equatable {
  /// Unique identifier for the message
  final String id;

  /// ID of the chat session this message belongs to
  final String sessionId;

  /// The actual text content of the message
  final String content;

  /// Who sent this message (user or AI)
  final MessageRole role;

  /// When the message was created
  final DateTime timestamp;

  /// Current status of the message (sending, sent, error)
  final MessageStatus status;

  /// Error message if status is error
  final String? error;

  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.content,
    required this.role,
    required this.timestamp,
    required this.status,
    this.error,
  });

  /// Create a copy of this message with some fields updated
  ChatMessage copyWith({
    String? id,
    String? sessionId,
    String? content,
    MessageRole? role,
    DateTime? timestamp,
    MessageStatus? status,
    String? error,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      content: content ?? this.content,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }

  /// Check if this is a user message
  bool get isUserMessage => role == MessageRole.user;

  /// Check if this is an AI message
  bool get isAIMessage => role == MessageRole.ai;

  /// Check if message is still being sent
  bool get isSending => status == MessageStatus.sending;

  /// Check if message was sent successfully
  bool get isSent => status == MessageStatus.sent;

  /// Check if there was an error sending
  bool get hasError => status == MessageStatus.error;

  @override
  List<Object?> get props => [
        id,
        sessionId,
        content,
        role,
        timestamp,
        status,
        error,
      ];

  @override
  String toString() {
    return 'ChatMessage(id: $id, role: $role, content: ${content.substring(0, content.length > 30 ? 30 : content.length)}..., status: $status)';
  }
}

/// Enum representing who sent the message
enum MessageRole {
  /// Message from the user
  user,

  /// Message from the AI assistant
  ai,
}

/// Enum representing the current status of a message
enum MessageStatus {
  /// Message is currently being sent
  sending,

  /// Message was sent successfully
  sent,

  /// There was an error sending the message
  error,
}

/// Extension to convert MessageRole to/from string for database storage
extension MessageRoleExtension on MessageRole {
  String toShortString() {
    return toString().split('.').last;
  }

  static MessageRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'user':
        return MessageRole.user;
      case 'ai':
        return MessageRole.ai;
      default:
        throw ArgumentError('Invalid message role: $role');
    }
  }
}

/// Extension to convert MessageStatus to/from string for database storage
extension MessageStatusExtension on MessageStatus {
  String toShortString() {
    return toString().split('.').last;
  }

  static MessageStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'error':
        return MessageStatus.error;
      default:
        throw ArgumentError('Invalid message status: $status');
    }
  }
}
