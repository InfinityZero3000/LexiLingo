import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';

const _tag = 'LexiChatRepositoryImpl';

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

  @override
  Future<LexiMessagesPage> getMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) {
    if (cursor == null || cursor.isEmpty) {
      return _getPagedWithMetadata(
        sessionId: sessionId,
        limit: limit,
        cursor: cursor,
      );
    }

    return dataSource.getMessagesPaged(
      sessionId: sessionId,
      limit: limit,
      cursor: cursor,
    );
  }

  Future<LexiMessagesPage> _getPagedWithMetadata({
    required String sessionId,
    required int limit,
    String? cursor,
  }) async {
    try {
      final metadata = await dataSource.getMessagesMetadata(sessionId: sessionId);
      if (!metadata.hasMessages || metadata.totalCount == 0) {
        return const LexiMessagesPage(
          messages: [],
          hasMore: false,
          nextCursor: null,
          returned: 0,
        );
      }
    } catch (e) {
      // Metadata endpoint is an optimization layer only.
      logWarn(_tag, 'getMessagesMetadata failed, continue paged fetch: $e');
    }

    return dataSource.getMessagesPaged(
      sessionId: sessionId,
      limit: limit,
      cursor: cursor,
    );
  }

  @override
  Future<List<LexiSession>> getSessions({required String userId}) {
    return dataSource.getSessions(userId: userId);
  }

  @override
  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) {
    return dataSource.renameSession(sessionId: sessionId, title: title);
  }

  @override
  Future<void> deleteSession({required String sessionId}) {
    return dataSource.deleteSession(sessionId: sessionId);
  }
}
