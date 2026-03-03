import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';

/// Abstract repository for Lexi chat operations.
abstract class LexiChatRepository {
  /// Create a new session with Lexi.
  Future<LexiSession> createSession({required String userId});

  /// Send a message to Lexi and get a response.
  Future<LexiMessage> sendMessage({
    required String userId,
    required String sessionId,
    required String message,
    String inputType = 'text',
    String? audioBase64,
    bool enableTts = true,
    String learnerLevel = 'B1',
    String? storyContext,
  });

  /// Get message history for a session.
  Future<List<LexiMessage>> getMessages({required String sessionId});
}
