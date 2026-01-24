import 'package:lexilingo_app/features/chat/domain/entities/message.dart';

class MessageModel extends Message {
  MessageModel({
    required String content,
    required bool isUser,
    required DateTime timestamp,
  }) : super(
          content: content,
          isUser: isUser,
          timestamp: timestamp,
        );

  // Convert from JSON to Model
  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      content: json['content'] as String,
      isUser: (json['isUser'] as int) == 1,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  // Convert from Model to JSON
  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'isUser': isUser ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Convert from Entity to Model
  factory MessageModel.fromEntity(Message entity) {
    return MessageModel(
      content: entity.content,
      isUser: entity.isUser,
      timestamp: entity.timestamp,
    );
  }
}
