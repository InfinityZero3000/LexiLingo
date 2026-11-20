import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/network/http_status.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_stream_event.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';

class _Repo extends Fake implements LexiChatRepository {
  Object? deleteError;
  Object? renameError;
  final Map<String, List<LexiSession>> remote = {};
  final List<String> created = [];

  @override
  Future<LexiSession> createSession({required String userId}) async {
    created.add(userId);
    return LexiSession(
      sessionId: 'new-$userId',
      userId: userId,
      createdAt: DateTime(2026, 1, 1),
      title: 'Lexi Chat',
    );
  }

  @override
  Future<List<LexiSession>> getSessions({required String userId}) async =>
      remote[userId] ?? const [];

  @override
  Future<LexiMessagesPage> getMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) async => const LexiMessagesPage(
    messages: [],
    hasMore: false,
    nextCursor: null,
    returned: 0,
  );

  @override
  Future<void> deleteSession({required String sessionId}) async {
    if (deleteError != null) throw deleteError!;
  }

  Completer<LexiMessage>? sendGate;
  StreamController<LexiStreamEvent>? stream;

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
  }) => sendGate!.future;

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
  }) => stream!.stream;

  @override
  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    if (renameError != null) throw renameError!;
  }
}

LexiSession _session(String id, String userId) => LexiSession(
  sessionId: id,
  userId: userId,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  title: 'Lexi Chat',
  messageCount: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Repo repo;
  late LexiChatProvider provider;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    repo = _Repo();
    provider = LexiChatProvider(repository: repo, aiClient: AiApiClient());
  });

  tearDown(() => provider.dispose());

  test(
    'restoring for another user does not keep the previous session',
    () async {
      await provider.startSession('user-a');
      expect(provider.session?.userId, 'user-a');
      repo.remote['user-b'] = [_session('b-1', 'user-b')];

      await provider.restoreLatestSession('user-b');

      expect(provider.session?.sessionId, 'b-1');
      expect(provider.sessions.every((s) => s.userId == 'user-b'), isTrue);
    },
  );

  test('restoring again for the same user keeps the open session', () async {
    await provider.startSession('user-a');

    await provider.restoreLatestSession('user-a');

    expect(provider.session?.sessionId, 'new-user-a');
    expect(repo.created, ['user-a']);
  });

  test('reset clears the conversation, the list and the saved copy', () async {
    await provider.startSession('user-a');
    await pumpEventQueue();
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'lexi_saved_sessions'), isNotNull);
    provider.setLearnerLevel('C1');

    provider.reset();
    await pumpEventQueue();

    expect(provider.session, isNull);
    expect(provider.sessions, isEmpty);
    expect(provider.messages, isEmpty);
    expect(provider.hasMoreMessages, isFalse);
    expect(provider.learnerLevel, 'B1');
    expect(await secure.read(key: 'lexi_saved_sessions'), isNull);
  });

  test('a session that lands after reset is ignored', () async {
    final starting = provider.startSession('user-a');
    provider.reset();
    await starting;

    expect(provider.session, isNull);
    expect(provider.sessions, isEmpty);
  });

  group('a session the server says belongs to someone else', () {
    setUp(() async {
      await provider.startSession('user-a');
    });

    test('delete reports the error instead of throwing', () async {
      repo.deleteError = Exception('Request failed with status 403 Forbidden');
      final id = provider.session!.sessionId;

      await provider.deleteSession(id);

      expect(provider.error, isNotNull);
      expect(provider.sessions.any((s) => s.sessionId == id), isFalse);
      expect(provider.session, isNull);
    });

    test('rename reports the error instead of throwing', () async {
      repo.renameError = Exception('Request failed with status 403 Forbidden');
      final id = provider.session!.sessionId;

      await provider.renameSession(id, 'New title');

      expect(provider.error, isNotNull);
      expect(provider.sessions.any((s) => s.sessionId == id), isFalse);
    });

    test(
      'a network failure keeps the session and shows a retry error',
      () async {
        repo.deleteError = Exception('SocketException: connection refused');
        final id = provider.session!.sessionId;

        await provider.deleteSession(id);

        expect(provider.error, isNotNull);
        expect(provider.sessions.any((s) => s.sessionId == id), isTrue);
        expect(provider.session?.sessionId, id);
      },
    );
  });

  group('status codes', () {
    test('a 403 inside an id is not a 403', () {
      expect(
        httpStatusOf(
          Exception(
            'Request /lexi/sessions/ab403cd1-0000/delete failed with status 500',
          ),
        ),
        500,
      );
      expect(httpStatusOf(Exception('socket closed: 10.0.0.403:8000')), isNull);
      expect(httpStatusOf(Exception('Request /x failed with status 403')), 403);
      expect(httpStatusOf(Exception('Forbidden')), 403);
    });

    test(
      'deleting a session with 403 in its id keeps it on a server error',
      () async {
        await provider.startSession('user-a');
        repo.created.clear();
        repo.deleteError = Exception(
          'Request /lexi/sessions/new-user-a403/delete failed with status 500',
        );
        final id = provider.session!.sessionId;

        await provider.deleteSession(id);

        expect(provider.sessions.any((s) => s.sessionId == id), isTrue);
        expect(provider.session?.sessionId, id);
        expect(provider.error, isNotNull);
      },
    );

    test('a 404 on delete removes the session locally', () async {
      await provider.startSession('user-a');
      repo.deleteError = Exception('Request /x failed with status 404');
      final id = provider.session!.sessionId;

      await provider.deleteSession(id);

      expect(provider.sessions.any((s) => s.sessionId == id), isFalse);
      expect(provider.session, isNull);
    });
  });

  group('a turn still running when the account changes', () {
    test('a reply that arrives after reset is not added', () async {
      await provider.startSession('user-a');
      repo.sendGate = Completer();
      final sending = provider.sendMessage('hello', userId: 'user-a');
      await pumpEventQueue();

      provider.reset();
      repo.sendGate!.complete(
        LexiMessage(
          id: 'r',
          role: 'assistant',
          content: 'for A only',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      await sending;

      expect(provider.messages, isEmpty);
      expect(provider.isSending, isFalse);
    });

    test('an open stream stops appending after reset', () async {
      await provider.startSession('user-a');
      repo.stream = StreamController<LexiStreamEvent>();
      final sending = provider.sendMessageStreaming('hello', userId: 'user-a');
      await pumpEventQueue();
      repo.stream!.add(const LexiStreamChunk('first '));
      await pumpEventQueue();
      expect(provider.messages.last.content, 'first ');

      provider.reset();
      repo.stream!.add(const LexiStreamChunk('for A only'));
      repo.stream!.add(
        const LexiStreamDone(
          messageId: 'm',
          sessionId: 's',
          corrections: [],
          linkedConcepts: [],
          metadata: {},
          audioBase64: 'AAAA',
        ),
      );
      await repo.stream!.close();
      await sending;

      expect(provider.messages, isEmpty);
      expect(provider.isSending, isFalse);
      expect(provider.isLexiResponding, isFalse);
    });
  });
}
