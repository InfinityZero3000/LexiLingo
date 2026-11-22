import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_stream_event.dart';
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
    String nativeLanguage = 'vi',
    String? storyContext,
    String? idempotencyKey,
  }) {
    return dataSource.sendMessage(
      userId: userId,
      sessionId: sessionId,
      message: message,
      inputType: inputType,
      audioBase64: audioBase64,
      enableTts: enableTts,
      learnerLevel: learnerLevel,
      nativeLanguage: nativeLanguage,
      storyContext: storyContext,
      idempotencyKey: idempotencyKey,
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
    // One round trip: the paged route already checks ownership and returns an
    // empty page for an empty session, so a metadata probe first only added a
    // second serial request (plus its CORS preflight on web).
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

  @override
  Future<Map<String, String>> getMemory() => dataSource.getMemory();

  @override
  Future<void> forgetMemory() => dataSource.forgetMemory();

  @override
  Future<void> forgetMemoryFact(String key) => dataSource.forgetMemoryFact(key);

  @override
  Stream<LexiStreamEvent> sendMessageStream({
    required String userId,
    required String sessionId,
    required String message,
    String inputType = 'text',
    String? audioBase64,
    bool enableTts = true,
    String learnerLevel = 'B1',
    String nativeLanguage = 'vi',
    String? storyContext,
    String? idempotencyKey,
  }) {
    return dataSource.sendMessageStream(
      userId: userId,
      sessionId: sessionId,
      message: message,
      inputType: inputType,
      audioBase64: audioBase64,
      enableTts: enableTts,
      learnerLevel: learnerLevel,
      nativeLanguage: nativeLanguage,
      storyContext: storyContext,
      idempotencyKey: idempotencyKey,
    );
  }
}
