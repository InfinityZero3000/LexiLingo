import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/auth/presentation/user_session_sync.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_session.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/create_session_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/get_chat_history_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/get_paged_chat_history_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/get_sessions_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/send_message_usecase.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Wallet extends Fake implements GamificationRepository {
  @override
  Future<WalletEntity> getWallet() async =>
      const WalletEntity(id: 'w', userId: 'a', gems: 300);
}

class _Lexi extends Fake implements LexiChatRepository {
  @override
  Future<LexiSession> createSession({required String userId}) async =>
      LexiSession(
        sessionId: 'a-session',
        userId: userId,
        createdAt: DateTime(2026, 1, 1),
        title: 'A chat',
      );

  @override
  Future<List<LexiSession>> getSessions({required String userId}) async => [];
}

class _Words extends Fake implements VocabRepository {
  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async => Right([
    VocabWord(id: 1, word: 'serendipity', definition: 'a happy accident'),
  ]);
}

class _ChatSessions extends Fake implements GetSessionsUseCase {
  @override
  Future<Either<Failure, List<ChatSession>>> call(String userId) async =>
      Right([
        ChatSession(
          id: 'c1',
          userId: userId,
          title: 'Chat',
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
}

class _NoCreate extends Fake implements CreateSessionUseCase {}

class _NoHistory extends Fake implements GetChatHistoryUseCase {}

class _NoPaged extends Fake implements GetPagedChatHistoryUseCase {}

class _NoSend extends Fake implements SendMessageUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GamificationProvider gamification;
  late LexiChatProvider lexi;
  late VocabProvider vocab;
  late ChatProvider chat;
  late BuildContext context;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'lexi_saved_sessions': '[]'});
    gamification = GamificationProvider(repository: _Wallet());
    lexi = LexiChatProvider(repository: _Lexi(), aiClient: AiApiClient());
    vocab = VocabProvider(
      getWordsUseCase: GetWordsUseCase(_Words()),
      addWordUseCase: AddWordUseCase(_Words()),
    );
    chat = ChatProvider(
      createSessionUseCase: _NoCreate(),
      getSessionsUseCase: _ChatSessions(),
      getChatHistoryUseCase: _NoHistory(),
      getPagedChatHistoryUseCase: _NoPaged(),
      sendMessageUseCase: _NoSend(),
    );
  });

  tearDown(() {
    gamification.dispose();
    lexi.dispose();
    vocab.dispose();
    chat.dispose();
  });

  Future<void> pumpScope(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: gamification),
          ChangeNotifierProvider.value(value: lexi),
          ChangeNotifierProvider.value(value: vocab),
          ChangeNotifierProvider.value(value: chat),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  testWidgets('signing out empties gems, Lexi, vocabulary and chat', (
    tester,
  ) async {
    await pumpScope(tester);
    await gamification.loadWallet();
    await lexi.startSession('user-a');
    await vocab.loadWords();
    await chat.loadSessions('user-a');
    expect(gamification.gems, 300);
    expect(lexi.session, isNotNull);
    expect(lexi.sessions, isNotEmpty);
    expect(vocab.words, isNotEmpty);
    expect(chat.sessions, isNotEmpty);

    UserSessionSync.afterSignOut(context);

    expect(gamification.gems, 0);
    expect(lexi.session, isNull);
    expect(lexi.sessions, isEmpty);
    expect(lexi.messages, isEmpty);
    expect(vocab.words, isEmpty);
    expect(chat.sessions, isEmpty);
  });

  testWidgets(
    'an account switch drops the old learner before the new one loads',
    (tester) async {
      await pumpScope(tester);
      await gamification.loadWallet();
      await vocab.loadWords();

      // The cache cleanup touches real storage, so it needs real time.
      await tester.runAsync(() async {
        final cleanup = UserSessionSync.beforeSignIn(
          context,
          SessionChange.accountSwitched,
        );
        expect(gamification.gems, 0, reason: 'reset before any await');
        expect(vocab.words, isEmpty);
        await cleanup;

        await UserSessionSync.afterSignIn(context);
        expect(vocab.words, isNotEmpty);
      });
    },
  );

  testWidgets('a first sign-in resets nothing', (tester) async {
    await pumpScope(tester);
    await gamification.loadWallet();

    await tester.runAsync(
      () => UserSessionSync.beforeSignIn(context, SessionChange.signedIn),
    );

    expect(gamification.gems, 300);
  });

  group('SessionTracker', () {
    test('reports each transition once', () {
      final t = SessionTracker();
      expect(t.update(authenticated: false), SessionChange.none);
      expect(
        t.update(authenticated: true, userId: 'a'),
        SessionChange.signedIn,
      );
      expect(t.update(authenticated: true, userId: 'a'), SessionChange.none);
      expect(t.update(authenticated: false), SessionChange.signedOut);
      expect(t.update(authenticated: false), SessionChange.none);
    });

    test('another user without a signed-out frame is an account switch', () {
      final t = SessionTracker();
      t.update(authenticated: true, userId: 'a');
      expect(
        t.update(authenticated: true, userId: 'b'),
        SessionChange.accountSwitched,
      );
      expect(t.update(authenticated: true, userId: 'b'), SessionChange.none);
    });

    test('a user id that arrives late is not mistaken for a switch', () {
      final t = SessionTracker();
      t.update(authenticated: true);
      expect(t.update(authenticated: true, userId: 'a'), SessionChange.none);
      expect(
        t.update(authenticated: true, userId: 'b'),
        SessionChange.accountSwitched,
      );
    });
  });
}
