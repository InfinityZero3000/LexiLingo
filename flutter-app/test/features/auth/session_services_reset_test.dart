import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/known_words_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/auth/presentation/user_session_sync.dart';
import 'package:lexilingo_app/features/chat/domain/entities/topic_session.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/story_repository.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/data/services/listening_history_recorder.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/social/data/repositories/social_repository.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';
import 'package:lexilingo_app/features/user/presentation/pages/settings_page.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Collection extends Fake implements VocabularyRepository {
  Completer<Either<Failure, List<UserVocabularyEntity>>>? gate;
  List<String> words = const [];

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getUserCollection({
    VocabularyStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final held = gate;
    if (held != null) return held.future;
    return Right([for (final w in words) _entry(w)]);
  }
}

UserVocabularyEntity _entry(String word) => UserVocabularyEntity(
  id: word,
  userId: 'u',
  vocabularyId: word,
  status: VocabularyStatus.learning,
  nextReviewDate: DateTime(2026, 1, 1),
  addedAt: DateTime(2026, 1, 1),
  word: word,
);

class _Stories extends Fake implements StoryRepository {
  final resumed = <String>[];
  int starts = 0;

  @override
  Future<Either<Failure, TopicMessagesPageResult>> getTopicMessagesPaged(
    String sessionId, {
    int limit = 20,
    String? cursor,
  }) async {
    resumed.add(sessionId);
    return const Left(ServerFailure('gone'));
  }

  @override
  Future<Either<Failure, TopicSession>> startTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'tracecag',
  }) async {
    starts++;
    return const Left(ServerFailure('no new session in this test'));
  }
}

class _Social extends Fake implements SocialRepository {}

class _SpySocial extends SocialProvider {
  _SpySocial() : super(repository: _Social());
  int resets = 0;

  @override
  void reset() {
    resets++;
    super.reset();
  }
}

class _Recorder extends PodcastRepository {}

const savedFor = '{"session_id":"a-session","story":{"story_id":"s1"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BuildContext context;

  Future<void> pumpScope(WidgetTester tester, List<SingleChildWidget> p) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: p.isEmpty ? [Provider<int>.value(value: 0)] : p,
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    UserSessionSync.debugResetBuildTracking();
    await sl.reset();
  });

  tearDown(() async => sl.reset());

  group('singletons outside the widget tree', () {
    testWidgets(
      'known words: sign-out drops the cache, a late answer is ignored',
      (tester) async {
        final repo = _Collection()..words = ['serendipity'];
        final service = KnownWordsService(vocabularyRepository: repo);
        sl.registerSingleton<KnownWordsService>(service);
        await pumpScope(tester, []);
        expect(await service.getKnownWords(), {'serendipity'});

        repo.gate = Completer();
        final late = service.getKnownWords(forceRefresh: true);
        UserSessionSync.afterSignOut(context);
        repo.gate!.complete(Right([_entry('secret')]));

        expect(await late, isEmpty, reason: 'the answer for A is dropped');
        repo.gate = null;
        repo.words = ['hello'];
        expect(await service.getKnownWords(), {'hello'});
      },
    );

    testWidgets('the podcast recorder forgets the episode', (tester) async {
      final repo = _SavedHistory();
      final recorder = ListeningHistoryRecorder(repo);
      sl.registerSingleton<ListeningHistoryRecorder>(recorder);
      await pumpScope(tester, []);
      recorder.track(
        episode: const PodcastEpisode(
          guid: 'a-ep',
          title: 't',
          audioUrl: 'u',
          durationSeconds: 100,
          feedUrl: 'f',
        ),
        podcastTitle: 'A',
        artworkUrl: '',
      );

      UserSessionSync.afterSignOut(context);
      recorder.onPlaying(true);
      recorder.onPosition(const Duration(seconds: 20));
      recorder.onPlaying(false);
      await recorder.flush();

      expect(repo.saved, isEmpty);
    });
  });

  group('providers nobody opened', () {
    testWidgets('sign-out does not construct them', (tester) async {
      var built = 0;
      await pumpScope(tester, [
        UserSessionSync.provider<SocialProvider>(() {
          built++;
          return _SpySocial();
        }),
      ]);

      UserSessionSync.afterSignOut(context);

      expect(built, 0);
    });

    testWidgets('a provider that was built is reset', (tester) async {
      await pumpScope(tester, [
        UserSessionSync.provider<SocialProvider>(() => _SpySocial()),
      ]);
      final spy = context.read<SocialProvider>() as _SpySocial;

      UserSessionSync.afterSignOut(context);

      expect(spy.resets, 1);
    });
  });

  group('topic sessions', () {
    test(
      'a saved session is only resumed by the account that saved it',
      () async {
        SharedPreferences.setMockInitialValues({
          'u:user-a:topic_session_s1': savedFor,
        });
        final stories = _Stories();
        final provider = StoryProvider(repository: stories);

        await UserScopeService.setActiveUserId('user-b');
        await provider.restoreOrStartTopicSession(
          userId: 'user-b',
          storyId: 's1',
        );
        expect(
          stories.resumed,
          isEmpty,
          reason: 'B never asks for A\'s session',
        );
        expect(stories.starts, 1);

        await UserScopeService.setActiveUserId('user-a');
        await provider.restoreOrStartTopicSession(
          userId: 'user-a',
          storyId: 's1',
        );
        expect(stories.resumed, ['a-session']);
        provider.dispose();
      },
    );
  });

  group('an account switch is the sign-out path', () {
    testWidgets('it resets providers and clears the caches sign-out clears', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'topic_session_s1': savedFor,
        'u:user-a:youtube_saved_videos': '[]',
      });
      FlutterSecureStorage.setMockInitialValues({'lexi_saved_sessions': '[]'});
      await pumpScope(tester, [
        UserSessionSync.provider<SocialProvider>(() => _SpySocial()),
      ]);
      final spy = context.read<SocialProvider>() as _SpySocial;

      await UserSessionSync.beforeSignIn(
        context,
        SessionChange.accountSwitched,
      );

      expect(spy.resets, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('topic_session_s1'), isFalse);
      expect(prefs.containsKey('u:user-a:youtube_saved_videos'), isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'lexi_saved_sessions'),
        isNull,
      );
    });

    testWidgets('a sign-in of the learner who owns the caches keeps them', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'topic_session_s1': savedFor,
        'cache_owner_user_id': 'user-a',
      });
      await pumpScope(tester, [
        UserSessionSync.provider<SocialProvider>(() => _SpySocial()),
      ]);
      final spy = context.read<SocialProvider>() as _SpySocial;

      await UserSessionSync.beforeSignIn(
        context,
        SessionChange.signedIn,
        userId: 'user-a',
      );

      expect(spy.resets, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('topic_session_s1'), isTrue);
    });

    testWidgets('a sign-in after a session that ended unnoticed clears them', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'topic_session_s1': savedFor,
        'cache_owner_user_id': 'user-a',
      });
      await pumpScope(tester, []);

      await UserSessionSync.beforeSignIn(
        context,
        SessionChange.signedIn,
        userId: 'user-b',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('topic_session_s1'), isFalse);
      expect(prefs.getString('cache_owner_user_id'), 'user-b');
    });
  });

  group('deliberate sign-out order', () {
    test('pending work first, then the session ends, then the pop', () async {
      final order = <String>[];
      var signedOut = false;

      final done = await performSignOut(
        flushPending: () async => order.add('flush'),
        signOut: () async {
          order.add('signOut');
          signedOut = true;
        },
        isSignedOut: () => signedOut,
        popToRoot: () => order.add('pop'),
      );

      expect(order, ['flush', 'signOut', 'pop']);
      expect(done, isTrue);
    });

    test('a flush that fails does not stop the sign-out', () async {
      final order = <String>[];

      await performSignOut(
        flushPending: () async => throw StateError('offline'),
        signOut: () async => order.add('signOut'),
        isSignedOut: () => true,
        popToRoot: () => order.add('pop'),
      );

      expect(order, ['signOut', 'pop']);
    });

    test('no pop when the learner is still signed in afterwards', () async {
      var popped = false;

      final done = await performSignOut(
        flushPending: () async {},
        signOut: () async {}, // AuthProvider.signOut swallows its errors
        isSignedOut: () => false,
        popToRoot: () => popped = true,
      );

      expect(done, isFalse);
      expect(popped, isFalse);
    });
  });

  group('providers across a rebuilt provider tree', () {
    testWidgets('a rebuild of the same tree changes nothing', (tester) async {
      var built = 0;
      Widget tree() => MultiProvider(
        providers: [
          UserSessionSync.provider<SocialProvider>(() {
            built++;
            return _SpySocial();
          }),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(tree());
      await tester.pumpWidget(tree()); // the root rebuilding
      UserSessionSync.afterSignOut(context);
      expect(built, 0, reason: 'never opened, so never built by a reset');

      final spy = context.read<SocialProvider>() as _SpySocial;
      await tester.pumpWidget(tree());
      UserSessionSync.afterSignOut(context);
      expect(built, 1);
      expect(spy.resets, 1);
    });
  });
}

class _SavedHistory extends _Recorder {
  final saved = <ListeningHistory>[];

  @override
  Future<ListeningHistory?> getListeningHistory(String episodeGuid) async =>
      null;

  @override
  Future<void> saveListeningHistory(ListeningHistory history) async =>
      saved.add(history);
}
