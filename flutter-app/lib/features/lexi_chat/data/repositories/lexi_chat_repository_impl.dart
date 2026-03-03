import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';

/// Repository implementation for Lexi Chat.
class LexiChatRepositoryImpl implements LexiChatRepository {
  final LexiChatDataSource dataSource;

  LexiChatRepositoryImpl({required this.dataSource});

  @override
  Future<LexiSession> createSession({required String userId}) {
    return dataSource.createSession(userId: userId);
  }

  @override
  Future<LexiMessage> sendMessage({
    required String userId,
    required String sessionId,
    required String message,
    String inputType = 'text',
    String? audioBase64,
    bool enableTts = true,
    String learnerLevel = 'B1',
    String? storyContext,
  }) {
    return dataSource.sendMessage(
      userId: userId,
      sessionId: sessionId,
      message: message,
      inputType: inputType,
      audioBase64: audioBase64,
      enableTts: enableTts,
      learnerLevel: learnerLevel,
      storyContext: storyContext,
    );
  }

  @override
  Future<List<LexiMessage>> getMessages({required String sessionId}) {
    return dataSource.getMessages(sessionId: sessionId);
  }
}
