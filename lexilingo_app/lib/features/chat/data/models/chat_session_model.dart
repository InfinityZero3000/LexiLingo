import '../../domain/entities/chat_session.dart';
import 'chat_message_model.dart';

/// Data model for ChatSession
/// Used to convert between domain entity and database/JSON
class ChatSessionModel extends ChatSession {
  const ChatSessionModel({
    required super.id,
    required super.userId,
    required super.title,
    required super.createdAt,
    super.lastMessageAt,
    super.messages,
  });

  /// Create model from domain entity
  factory ChatSessionModel.fromEntity(ChatSession entity) {
    return ChatSessionModel(
      id: entity.id,
      userId: entity.userId,
      title: entity.title,
      createdAt: entity.createdAt,
      lastMessageAt: entity.lastMessageAt,
      messages: entity.messages,
    );
  }

  /// Convert to domain entity
  ChatSession toEntity() {
    return ChatSession(
      id: id,
      userId: userId,
      title: title,
      createdAt: createdAt,
      lastMessageAt: lastMessageAt,
      messages: messages,
    );
  }

  /// Create from database map
  factory ChatSessionModel.fromMap(Map<String, dynamic> map) {
    return ChatSessionModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int)
          : null,
      messages: null, // Messages loaded separately
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_message_at': lastMessageAt?.millisecondsSinceEpoch,
    };
  }

  /// Create from JSON
  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    return ChatSessionModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'] as String)
          : null,
      messages: json['messages'] != null
          ? (json['messages'] as List)
              .map((m) => ChatMessageModel.fromJson(m as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'lastMessageAt': lastMessageAt?.toIso8601String(),
      'messages': messages?.map((m) {
        if (m is ChatMessageModel) {
          return m.toJson();
        }
        return ChatMessageModel.fromEntity(m).toJson();
      }).toList(),
    };
  }

  /// Create a copy with updated fields
  @override
  ChatSessionModel copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    List? messages,
  }) {
    return ChatSessionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messages: messages ?? this.messages,
    );
  }
}
