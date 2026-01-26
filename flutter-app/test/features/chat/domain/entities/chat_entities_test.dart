import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_message.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_session.dart';

void main() {
  group('Chat Entities Tests', () {
    test('ChatMessage entity should be created correctly', () {
      // Arrange
      final timestamp = DateTime.now();
      
      // Act
      final message = ChatMessage(
        id: '1',
        sessionId: 'session_1',
        content: 'Hello, how are you?',
        role: MessageRole.user,
        timestamp: timestamp,
        status: MessageStatus.sent,
      );

      // Assert
      expect(message.id, '1');
      expect(message.content, 'Hello, how are you?');
      expect(message.role, MessageRole.user);
      expect(message.status, MessageStatus.sent);
      expect(message.isUserMessage, true);
      expect(message.isAIMessage, false);
      expect(message.isSent, true);
    });

    test('ChatMessage copyWith should work correctly', () {
      // Arrange
      final original = ChatMessage(
        id: '1',
        sessionId: 'session_1',
        content: 'Test',
        role: MessageRole.user,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
      );

      // Act
      final updated = original.copyWith(
        status: MessageStatus.sent,
      );

      // Assert
      expect(updated.id, original.id);
      expect(updated.status, MessageStatus.sent);
      expect(original.status, MessageStatus.sending);
    });

    test('ChatSession entity should be created correctly', () {
      // Arrange
      final now = DateTime.now();
      
      // Act
      final session = ChatSession(
        id: 'session_1',
        userId: 'user_1',
        title: 'Test Chat',
        createdAt: now,
      );

      // Assert
      expect(session.id, 'session_1');
      expect(session.title, 'Test Chat');
      expect(session.isEmpty, true);
      expect(session.hasMessages, false);
    });

    test('ChatSession should handle messages correctly', () {
      // Arrange
      final messages = [
        ChatMessage(
          id: '1',
          sessionId: 'session_1',
          content: 'Hello',
          role: MessageRole.user,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ),
        ChatMessage(
          id: '2',
          sessionId: 'session_1',
          content: 'Hi there!',
          role: MessageRole.ai,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ),
      ];

      // Act
      final session = ChatSession(
        id: 'session_1',
        userId: 'user_1',
        title: 'Test Chat',
        createdAt: DateTime.now(),
        messages: messages,
      );

      // Assert
      expect(session.messageCount, 2);
      expect(session.hasMessages, true);
      expect(session.isEmpty, false);
      expect(session.lastMessage?.content, 'Hi there!');
    });

    test('MessageRole enum should convert to/from string', () {
      // Test toShortString
      expect(MessageRole.user.toShortString(), 'user');
      expect(MessageRole.ai.toShortString(), 'ai');

      // Test fromString
      expect(MessageRoleExtension.fromString('user'), MessageRole.user);
      expect(MessageRoleExtension.fromString('ai'), MessageRole.ai);
    });

    test('MessageStatus enum should convert to/from string', () {
      // Test toShortString
      expect(MessageStatus.sending.toShortString(), 'sending');
      expect(MessageStatus.sent.toShortString(), 'sent');
      expect(MessageStatus.error.toShortString(), 'error');

      // Test fromString
      expect(MessageStatusExtension.fromString('sending'), MessageStatus.sending);
      expect(MessageStatusExtension.fromString('sent'), MessageStatus.sent);
      expect(MessageStatusExtension.fromString('error'), MessageStatus.error);
    });
  });
}
