import '../../domain/entities/chat_message.dart';

/// Data model for ChatMessage
/// Used to convert between domain entity and database/JSON
class ChatMessageModel extends ChatMessage {
  const ChatMessageModel({
    required super.id,
    required super.sessionId,
    required super.content,
    required super.role,
    required super.timestamp,
    required super.status,
    super.error,
  });

  /// Create model from domain entity
  factory ChatMessageModel.fromEntity(ChatMessage entity) {
    return ChatMessageModel(
      id: entity.id,
      sessionId: entity.sessionId,
      content: entity.content,
      role: entity.role,
      timestamp: entity.timestamp,
      status: entity.status,
      error: entity.error,
    );
  }

  /// Convert to domain entity
  ChatMessage toEntity() {
    return ChatMessage(
      id: id,
      sessionId: sessionId,
      content: content,
      role: role,
      timestamp: timestamp,
      status: status,
      error: error,
    );
  }

  /// Create from database map
  factory ChatMessageModel.fromMap(Map<String, dynamic> map) {
    return ChatMessageModel(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      content: map['content'] as String,
      role: MessageRoleExtension.fromString(map['role'] as String),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      status: MessageStatusExtension.fromString(map['status'] as String),
      error: map['error'] as String?,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'content': content,
      'role': role.toShortString(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status.toShortString(),
      'error': error,
    };
  }

  /// Create from JSON
  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      content: json['content'] as String,
      role: MessageRoleExtension.fromString(json['role'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: MessageStatusExtension.fromString(json['status'] as String),
      error: json['error'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'content': content,
      'role': role.toShortString(),
      'timestamp': timestamp.toIso8601String(),
      'status': status.toShortString(),
      'error': error,
    };
  }

  /// Create a copy with updated fields
  @override
  ChatMessageModel copyWith({
    String? id,
    String? sessionId,
    String? content,
    MessageRole? role,
    DateTime? timestamp,
    MessageStatus? status,
    String? error,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      content: content ?? this.content,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}
