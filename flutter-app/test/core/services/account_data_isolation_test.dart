import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/account_data_cleaner.dart';
import 'package:lexilingo_app/core/services/local_cache_service.dart';
import 'package:lexilingo_app/core/services/encrypted_local_cache_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/notifications/data/datasources/notification_local_datasource.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/vocabulary/data/repositories/vocab_repository_impl.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends Fake implements ApiClient {
  _Api({required this.fail});

  bool fail;
  int? failAfter;
  final errors = <String, Object>{};
  Completer<void>? gate;
  void Function(String word)? afterPost;
  Map<String, String>? lastHeaders;
  final posted = <Map<String, dynamic>>[];
  final attempted = <String>[];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final word = (body! as Map)['word'] as String;
    lastHeaders = headers;
    attempted.add(word);
    final held = gate;
    if (held != null) {
      gate = null;
      await held.future;
    }
    if (errors.containsKey(word)) throw errors[word]!;
    if (fail || (failAfter != null && posted.length >= failAfter!)) {
      throw Exception('offline');
    }
    posted.add(Map<String, dynamic>.from(body as Map));
    afterPost?.call(word);
    return {};
  }
}

Future<void> _signInAs(String userId) =>
    UserScopeService.setActiveUserId(userId);

List<VocabWord> _words(Either<dynamic, List<VocabWord>> result) =>
    result.getOrElse(() => const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await EncryptedLocalCacheService.instance.clearAll();
  });

  group('web vocabulary', () {
    const legacy = '[{"word":"secret","definition":"added before accounts"}]';

    test('the first account to sign in claims the old global list', () async {
      SharedPreferences.setMockInitialValues({'vocab_words_json': legacy});
      await _signInAs('user-b');
      final api = _Api(fail: true);
      final repo = VocabRepositoryImpl(localDataSource: null, apiClient: api);

      expect(_words(await repo.getWords()).map((w) => w.word), ['secret']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('vocab_words_json'), isFalse);
      await _signInAs('user-c');
      expect(_words(await repo.getWords()), isEmpty);
    });

    test('nobody claims it while anonymous', () async {
      SharedPreferences.setMockInitialValues({'vocab_words_json': legacy});

      final result = await VocabRepositoryImpl(
        localDataSource: null,
      ).getWords();

      expect(_words(result), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('vocab_words_json'), isTrue);
    });

    test('a word is kept until the server has it, then dropped', () async {
      await _signInAs('user-a');
      final api = _Api(fail: true);
      final repo = VocabRepositoryImpl(localDataSource: null, apiClient: api);

      await repo.addWord(VocabWord(word: 'lucid', definition: 'clear'));
      expect(_words(await repo.getWords()).map((w) => w.word), ['lucid']);
      expect(api.posted, isEmpty);

      api.fail = false;
      final after = await repo.getWords();

      expect(api.posted.single['word'], 'lucid');
      expect(
        _words(after),
        isEmpty,
        reason: 'the server collection has it now',
      );
    });

    test('words go out oldest first and a failure keeps the rest', () async {
      await _signInAs('user-a');
      final api = _Api(fail: true);
      final repo = VocabRepositoryImpl(localDataSource: null, apiClient: api);
      await repo.addWord(VocabWord(word: 'one', definition: '1'));
      await repo.addWord(VocabWord(word: 'two', definition: '2'));
      api.fail = false;
      api.failAfter = 1;

      final left = await repo.getWords();

      expect(api.posted.map((p) => p['word']), ['one']);
      expect(_words(left).map((w) => w.word), ['two']);
    });

    test('a word added while another is being sent is not lost', () async {
      await _signInAs('user-a');
      final api = _Api(fail: true);
      final repo = VocabRepositoryImpl(localDataSource: null, apiClient: api);
      await repo.addWord(VocabWord(word: 'one', definition: '1')); // stays
      final held = Completer<void>();
      api
        ..fail = false
        ..failAfter = 1
        ..gate = held;

      final flushing = repo.getWords();
      await pumpEventQueue();
      expect(api.attempted.last, 'one', reason: 'the request is in flight');
      await repo.addWord(VocabWord(word: 'two', definition: '2'));
      held.complete();
      await flushing;

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(
        prefs.getString('u:user-a:vocab_pending_words')!,
      );
      expect((stored as List).map((w) => w['word']), ['two']);
    });

    test(
      'nothing is sent for the old learner after the scope changes',
      () async {
        await _signInAs('user-a');
        final api = _Api(fail: true);
        final repo = VocabRepositoryImpl(localDataSource: null, apiClient: api);
        await repo.addWord(VocabWord(word: 'one', definition: '1'));
        await repo.addWord(VocabWord(word: 'two', definition: '2'));
        api
          ..fail = false
          ..afterPost = (_) => UserScopeService.setActiveUserId('user-b');

        await repo.getWords();

        expect(api.posted.map((p) => p['word']), ['one']);
        final prefs = await SharedPreferences.getInstance();
        final left = jsonDecode(
          prefs.getString('u:user-a:vocab_pending_words')!,
        );
        expect((left as List).map((w) => w['word']), ['two']);
        expect(prefs.containsKey('u:user-b:vocab_pending_words'), isFalse);
      },
    );

    test(
      'a word the server refuses for good is dropped, the rest go on',
      () async {
        for (final status in [400, 409, 422]) {
          SharedPreferences.setMockInitialValues({});
          await _signInAs('user-a');
          final api = _Api(fail: true);
          final repo = VocabRepositoryImpl(
            localDataSource: null,
            apiClient: api,
          );
          await repo.addWord(VocabWord(word: 'bad', definition: 'x'));
          await repo.addWord(VocabWord(word: 'good', definition: 'y'));
          api
            ..fail = false
            ..errors['bad'] = ServerException(
              'Request /vocabulary/collection/quick-save failed with status $status',
            );

          final left = await repo.getWords();

          expect(api.posted.map((p) => p['word']), ['good'], reason: '$status');
          expect(_words(left), isEmpty, reason: '$status');
        }
      },
    );

    test('a failure that may pass keeps the word and stops', () async {
      final transient = <String, Object>{
        '401': const ServerException('failed with status 401'),
        '500': const ServerException('failed with status 500'),
        '503': const ServerException('failed with status 503'),
        'timeout': TimeoutException('slow'),
        'unknown': StateError('who knows'),
      };
      for (final entry in transient.entries) {
        SharedPreferences.setMockInitialValues({});
        await _signInAs('user-a');
        final api = _Api(fail: true);
        final repo = VocabRepositoryImpl(localDataSource: null, apiClient: api);
        await repo.addWord(VocabWord(word: 'first', definition: 'x'));
        await repo.addWord(VocabWord(word: 'second', definition: 'y'));
        api
          ..fail = false
          ..errors['first'] = entry.value;

        final left = await repo.getWords();

        expect(api.attempted.last, 'first', reason: entry.key);
        expect(api.posted, isEmpty, reason: entry.key);
        expect(_words(left).map((w) => w.word).toSet(), {
          'first',
          'second',
        }, reason: entry.key);
      }
    });

    test('the request carries no idempotency header', () async {
      await _signInAs('user-a');
      final api = _Api(fail: false);
      final repo = VocabRepositoryImpl(localDataSource: null, apiClient: api);

      await repo.addWord(VocabWord(word: 'lucid', definition: 'clear'));

      expect(api.posted, hasLength(1));
      expect(api.lastHeaders, isNull);
    });

    test('user B never sees the words user A has pending', () async {
      final repo = VocabRepositoryImpl(
        localDataSource: null,
        apiClient: _Api(fail: true),
      );
      await _signInAs('user-a');
      await repo.addWord(VocabWord(word: 'lucid', definition: 'clear'));

      await _signInAs('user-b');
      expect(_words(await repo.getWords()), isEmpty);

      await _signInAs('user-a');
      expect(_words(await repo.getWords()).map((w) => w.word), ['lucid']);
    });

    test('saving a word writes no global key', () async {
      await _signInAs('user-a');

      await VocabRepositoryImpl(
        localDataSource: null,
      ).addWord(VocabWord(word: 'lucid', definition: 'clear'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('vocab_words_json'), isFalse);
    });
  });

  group('sign-out removes caches only', () {
    test(
      'only cache keys go; unclaimed device data and the rest stay',
      () async {
        SharedPreferences.setMockInitialValues({
          'vocab_words_json': '[]',
          'topic_session_story1': '{}',
          'recent_topic_ids': ['s1'],
          'notifications': '[]',
          'book_progress_b1': '{}',
          'u:user-a:youtube_saved_videos': '[]',
          'u:user-a:book_progress_b1': '{}',
          'reader_settings': '{}',
          'dismissed_promo_banner_ids': ['p1'],
          'pre_auth_answers_pending': '{}',
        });
        FlutterSecureStorage.setMockInitialValues({
          'lexi_saved_sessions': '[]',
          'unrelated': 'x',
        });

        await AccountDataCleaner.clear();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {
          'vocab_words_json',
          'recent_topic_ids',
          'notifications',
          'book_progress_b1',
          'u:user-a:youtube_saved_videos',
          'u:user-a:book_progress_b1',
          'reader_settings',
          'dismissed_promo_banner_ids',
          'pre_auth_answers_pending',
        });
        const secure = FlutterSecureStorage();
        expect(await secure.read(key: 'lexi_saved_sessions'), isNull);
        expect(await secure.read(key: 'unrelated'), 'x');
      },
    );
  });

  group('legacy device-only data', () {
    const legacy = {
      'recent_topic_ids': ['s1'],
      'recent_topic_ids_data': ['{}'],
      'notifications': '[{"id":"n"}]',
      'youtube_saved_videos': '[1]',
      'youtube_watch_history': '[2]',
      'podcast_follows': ['f'],
      'podcast_listening_history': ['h'],
      'book_saved_ids': ['b1'],
      'book_progress_b1': '{"p":1}',
      'book_reading_data_b1': '{"r":1}',
      'book_saved_data_b1': '{"s":1}',
      'book_bookmarks_b1': '[3]',
    };

    test('the first signed-in user claims it, the next sees nothing', () async {
      SharedPreferences.setMockInitialValues({
        ...legacy,
        'reader_settings': '{}',
      });

      await _signInAs('user-a');

      final prefs = await SharedPreferences.getInstance();
      for (final entry in legacy.entries) {
        expect(prefs.containsKey(entry.key), isFalse, reason: entry.key);
        expect(
          prefs.get('u:user-a:${entry.key}'),
          entry.value,
          reason: entry.key,
        );
      }
      expect(prefs.containsKey('reader_settings'), isTrue);

      await _signInAs('user-b');
      expect(prefs.getKeys().where((k) => k.startsWith('u:user-b:')), isEmpty);
      expect(await PodcastRepository().getFollowedPodcasts(), isEmpty);
    });

    test('claiming twice changes nothing', () async {
      SharedPreferences.setMockInitialValues({...legacy});
      await _signInAs('user-a');
      final prefs = await SharedPreferences.getInstance();
      final once = {for (final k in prefs.getKeys()) k: prefs.get(k)};

      await _signInAs('user-a');

      expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, once);
    });

    test(
      'an existing scoped value is kept, the global one still goes',
      () async {
        SharedPreferences.setMockInitialValues({
          'notifications': 'old',
          'u:user-a:notifications': 'mine',
        });

        await _signInAs('user-a');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('u:user-a:notifications'), 'mine');
        expect(prefs.containsKey('notifications'), isFalse);
      },
    );

    test(
      'a legacy list is merged into a scoped one, never discarded',
      () async {
        SharedPreferences.setMockInitialValues({
          'podcast_follows': ['b', 'c'],
          'u:user-a:podcast_follows': ['a', 'b'],
        });

        await _signInAs('user-a');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('u:user-a:podcast_follows'), [
          'a',
          'b',
          'c',
        ]);
        expect(prefs.containsKey('podcast_follows'), isFalse);
      },
    );

    test('a push that arrived first keeps the old notifications too', () async {
      SharedPreferences.setMockInitialValues({
        'notifications': '[{"id":"old"},{"id":"both"}]',
        'u:user-a:notifications': '[{"id":"new"},{"id":"both"}]',
      });

      await _signInAs('user-a');

      final prefs = await SharedPreferences.getInstance();
      final merged = jsonDecode(prefs.getString('u:user-a:notifications')!);
      expect((merged as List).map((e) => e['id']), ['new', 'both', 'old']);
      expect(prefs.containsKey('notifications'), isFalse);
    });

    test('values that are not lists keep the scoped one', () async {
      SharedPreferences.setMockInitialValues({
        'book_progress_b1': '{"p":"old"}',
        'u:user-a:book_progress_b1': '{"p":"mine"}',
      });

      await _signInAs('user-a');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('u:user-a:book_progress_b1'), '{"p":"mine"}');
    });

    test('no one claims it while anonymous', () async {
      SharedPreferences.setMockInitialValues({...legacy});

      await _signInAs('anonymous');
      await _signInAs('');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), legacy.keys.toSet().union({'active_user_id'}));
    });

    test('a claimed podcast follow is the learner\'s own afterwards', () async {
      SharedPreferences.setMockInitialValues({
        'podcast_follows': [
          jsonEncode({
            'feed_url': 'https://x/feed',
            'podcast_title': 'Pod',
            'artwork_url': '',
            'followed_at': '2026-01-01T00:00:00.000',
          }),
        ],
      });

      await _signInAs('user-a');

      expect(await PodcastRepository().isFollowing('https://x/feed'), isTrue);
    });
  });

  group('device-only data is per learner', () {
    test('podcast follows and history', () async {
      final repo = PodcastRepository();
      await _signInAs('user-a');
      await repo.followPodcast(
        const Podcast(id: 'p', title: 'Pod', feedUrl: 'https://x/feed'),
      );
      expect(await repo.isFollowing('https://x/feed'), isTrue);

      await _signInAs('user-b');
      expect(await repo.isFollowing('https://x/feed'), isFalse);
      expect(await repo.getFollowedPodcasts(), isEmpty);

      await _signInAs('user-a');
      expect(await repo.getFollowedPodcasts(), hasLength(1));
    });

    test('saved books and reading progress', () async {
      final repo = BookRepository();
      await _signInAs('user-a');
      final book = Book(
        id: 'b1',
        title: 'T',
        author: 'A',
        coverUrl: '',
        cefrLevel: 'B1',
        topic: 'Fantasy',
        chapterCount: 1,
        wordCount: 10,
      );
      await repo.saveBook(book);
      await repo.saveProgress(
        UserBook(
          bookId: 'b1',
          currentPage: 3,
          totalPages: 10,
          readingProgress: 0.3,
          lastReadAt: DateTime(2026, 1, 1),
        ),
      );

      await _signInAs('user-b');
      expect(await repo.isBookSaved('b1'), isFalse);
      expect(await repo.getSavedBooks(), isEmpty);
      expect(await repo.getAllProgress(), isEmpty);

      await _signInAs('user-a');
      expect(await repo.getSavedBooks(), hasLength(1));
      expect(await repo.getAllProgress(), hasLength(1));
    });

    test('notifications', () async {
      final source = NotificationLocalDataSourceImpl();
      await _signInAs('user-a');
      await source.addNotification(
        NotificationEntity(
          id: 'n1',
          type: NotificationType.general,
          title: 'Hi',
          body: 'A only',
          timestamp: DateTime(2026, 1, 1),
          isRead: false,
        ),
      );
      expect(await source.getNotifications(), hasLength(1));

      await _signInAs('user-b');
      expect(await source.getNotifications(), isEmpty);
    });
  });

  group('shared offline cache', () {
    test('only the learner\'s own entries count as per-user', () {
      for (final key in [
        'proficiency:profile:v1',
        'due_vocab_20',
        'xp:profile:v1',
        'xp:leaderboard:limit:20',
      ]) {
        expect(LocalCacheService.isPerUserKey(key), isTrue, reason: key);
      }
      for (final key in [
        'news:categories',
        'books:recommended:all',
        'podcast:curated',
        'youtube:captions:v2:abc:en',
        'youtube:translate:hello:vi',
      ]) {
        expect(LocalCacheService.isPerUserKey(key), isFalse, reason: key);
      }
    });
  });
}
