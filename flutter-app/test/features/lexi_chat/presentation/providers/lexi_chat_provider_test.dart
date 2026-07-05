import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_stream_event.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';

class _FakeLexiChatRepository implements LexiChatRepository {
  int createSessionCalls = 0;
  int sendCalls = 0;
  int streamCalls = 0;
  String? lastIdempotencyKey;
  Object? pagedError;
  Stream<LexiStreamEvent> Function()? streamFactory;

  @override
  Future<LexiSession> createSession({required String userId}) async {
    createSessionCalls += 1;
    return LexiSession(
      sessionId: 's-1',
      userId: userId,
      createdAt: DateTime.parse('2026-05-30T00:00:00Z'),
      title: 'Lexi Chat',
    );
  }

  @override
  Future<void> deleteSession({required String sessionId}) async {}

  @override
  Future<List<LexiMessage>> getMessages({required String sessionId}) async {
    return const [];
  }

  @override
  Future<LexiMessagesPage> getMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) async {
    if (pagedError != null) {
      throw pagedError!;
    }
    return const LexiMessagesPage(
      messages: [],
      hasMore: false,
      nextCursor: null,
      returned: 0,
    );
  }

  @override
  Future<List<LexiSession>> getSessions({required String userId}) async {
    return const [];
  }

  @override
  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {}

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
    String? idempotencyKey,
  }) async {
    sendCalls += 1;
    lastIdempotencyKey = idempotencyKey;
    return LexiMessage(
      id: 'assistant-$sendCalls',
      role: 'assistant',
      content: 'ok',
      timestamp: DateTime.parse('2026-05-30T00:00:01Z'),
    );
  }

  @override
  Stream<LexiStreamEvent> sendMessageStream({
    required String userId,
    required String sessionId,
    required String message,
    String inputType = 'text',
    String? audioBase64,
    bool enableTts = true,
    String learnerLevel = 'B1',
    String? storyContext,
  }) {
    streamCalls += 1;
    return streamFactory?.call() ??
        Stream<LexiStreamEvent>.fromIterable([
          const LexiStreamChunk('ok'),
          const LexiStreamDone(
            messageId: 'stream-assistant-1',
            sessionId: 's-1',
            corrections: [],
            linkedConcepts: [],
            metadata: {},
          ),
        ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LexiChatProvider', () {
    test('builds web-safe request ids without crypto random', () async {
      final repo = _FakeLexiChatRepository();
      final provider = LexiChatProvider(
        repository: repo,
        aiClient: AiApiClient(),
      );
      addTearDown(provider.dispose);

      await provider.sendMessage('hello', userId: 'user@example.com');

      expect(repo.createSessionCalls, 1);
      expect(repo.sendCalls, 1);
      expect(
        repo.lastIdempotencyKey,
        matches(RegExp(r'^lexi-user_example\.com-s-1-\d+-1$')),
      );
      expect(repo.lastIdempotencyKey, isNot(contains('@')));
      expect(provider.isSending, isFalse);
      expect(provider.messages.where((m) => m.role == 'user').length, 1);
      expect(provider.messages.last.content, 'ok');
    });

    test('falls back to non-streaming send when SSE closes empty', () async {
      final repo = _FakeLexiChatRepository()
        ..streamFactory = () => const Stream<LexiStreamEvent>.empty();
      final provider = LexiChatProvider(
        repository: repo,
        aiClient: AiApiClient(),
      );
      addTearDown(provider.dispose);

      await provider.sendMessageStreaming('hello', userId: 'user-1');

      expect(repo.streamCalls, 1);
      expect(repo.sendCalls, 1);
      expect(provider.isSending, isFalse);
      expect(provider.isLexiResponding, isFalse);
      expect(provider.messages.any((m) => m.syncStatus == 'streaming'), false);
      expect(provider.messages.where((m) => m.role == 'user').length, 1);
      expect(provider.messages.last.content, 'ok');
    });

    test('keeps streamed text when SSE has chunks but no done event', () async {
      final repo = _FakeLexiChatRepository()
        ..streamFactory = () => Stream<LexiStreamEvent>.fromIterable([
          const LexiStreamThinking(),
          const LexiStreamChunk('Hi'),
          const LexiStreamChunk(' there'),
        ]);
      final provider = LexiChatProvider(
        repository: repo,
        aiClient: AiApiClient(),
      );
      addTearDown(provider.dispose);

      await provider.sendMessageStreaming('hello', userId: 'user-1');

      expect(repo.streamCalls, 1);
      expect(repo.sendCalls, 0);
      expect(provider.isSending, isFalse);
      expect(provider.isLexiResponding, isFalse);
      expect(provider.messages.any((m) => m.syncStatus == 'streaming'), false);
      expect(provider.messages.last.role, 'assistant');
      expect(provider.messages.last.content, 'Hi there');
      expect(provider.messages.last.syncStatus, 'synced');
    });

    test('clears selected session when backend returns forbidden', () async {
      final repo = _FakeLexiChatRepository()
        ..pagedError = Exception(
          'Request /lexi/sessions/old/messages/metadata failed with status 403',
        );
      final provider = LexiChatProvider(
        repository: repo,
        aiClient: AiApiClient(),
      );
      addTearDown(provider.dispose);

      await provider.selectSession(
        LexiSessionSummary(
          sessionId: 'old',
          userId: 'other-user',
          title: 'Old session',
          createdAt: DateTime.parse('2026-05-30T00:00:00Z'),
          updatedAt: DateTime.parse('2026-05-30T00:00:00Z'),
          messageCount: 1,
        ),
      );

      expect(provider.session, isNull);
      expect(provider.messages, isEmpty);
      expect(provider.error, contains('another account'));
    });
  });
}
