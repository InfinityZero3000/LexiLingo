import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/vocabulary/data/repositories/vocab_repository_impl.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLexiRepo implements LexiChatRepository {
  _FakeLexiRepo({required this.initialMessages});

  final List<LexiMessage> initialMessages;
  bool failPagedFetch = false;

  @override
  Future<LexiSession> createSession({required String userId}) async {
    return LexiSession(
      sessionId: 's-1',
      userId: userId,
      createdAt: DateTime.now(),
      title: 'Session',
    );
  }

  @override
  Future<void> deleteSession({required String sessionId}) async {}

  @override
  Future<List<LexiMessage>> getMessages({required String sessionId}) async {
    return initialMessages;
  }

  @override
  Future<LexiMessagesPage> getMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) async {
    if (failPagedFetch) {
      throw Exception('offline');
    }
    return LexiMessagesPage(
      messages: initialMessages,
      hasMore: false,
      nextCursor: null,
      returned: initialMessages.length,
    );
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
    return LexiMessage(
      id: 'assistant-1',
      role: 'assistant',
      content: 'ok',
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<List<LexiSession>> getSessions({required String userId}) async {
    return [
      LexiSession(
        sessionId: 's-1',
        userId: userId,
        createdAt: DateTime.now(),
        title: 'Session',
      ),
    ];
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
    return Stream.empty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Smoke: vocab + lexi offline restore', () {
    test('vocab add/get uses user-scoped local-first path', () async {
      SharedPreferences.setMockInitialValues({});
      await UserScopeService.setActiveUserId('smoke-user-1');

      final repo = VocabRepositoryImpl(localDataSource: null);
      final add = await repo.addWord(
        VocabWord(word: 'resilient', definition: 'able to recover quickly'),
      );
      expect(add.isRight(), isTrue);

      final wordsResult = await repo.getWords();
      expect(wordsResult.isRight(), isTrue);
      wordsResult.fold(
        (_) => fail('Expected words list'),
        (words) {
          expect(words.any((w) => w.word == 'resilient'), isTrue);
        },
      );
    });

    test('lexi session restore keeps cached messages when offline', () async {
      final fakeRepo = _FakeLexiRepo(
        initialMessages: [
          LexiMessage(
            id: 'm-1',
            role: 'assistant',
            content: 'cached hello',
            timestamp: DateTime.now(),
          ),
        ],
      );

      final provider = LexiChatProvider(repository: fakeRepo);
      final summary = LexiSessionSummary(
        sessionId: 's-1',
        userId: 'smoke-user-1',
        title: 'Session',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messageCount: 1,
      );

      await provider.selectSession(summary);
      expect(provider.messages.isNotEmpty, isTrue);
      expect(provider.messages.first.content, 'cached hello');

      fakeRepo.failPagedFetch = true;
      await provider.selectSession(summary);

      expect(provider.messages.isNotEmpty, isTrue);
      expect(provider.messages.first.content, 'cached hello');
    });
  });
}
