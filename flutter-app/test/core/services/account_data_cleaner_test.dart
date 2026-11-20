import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/account_data_cleaner.dart';
import 'package:lexilingo_app/core/services/local_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'lexi_saved_sessions': '[]'});
  });

  tearDown(() {
    AccountDataCleaner.stepTimeout = const Duration(seconds: 2);
    AccountDataCleaner.debugUserCacheClear = null;
  });

  test('a storage step that never answers cannot hold sign-out up', () async {
    SharedPreferences.setMockInitialValues({'topic_session_s1': '{}'});
    AccountDataCleaner.stepTimeout = const Duration(milliseconds: 50);
    AccountDataCleaner.debugUserCacheClear = () => Completer<void>().future;

    await AccountDataCleaner.clear().timeout(const Duration(seconds: 5));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('topic_session_s1'), isFalse);
    expect(
      await const FlutterSecureStorage().read(key: 'lexi_saved_sessions'),
      isNull,
      reason: 'the steps that did answer still ran',
    );
  });

  test('a step that throws does not stop the others', () async {
    SharedPreferences.setMockInitialValues({'topic_session_s1': '{}'});
    AccountDataCleaner.debugUserCacheClear = () async => throw StateError('db');

    await AccountDataCleaner.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('topic_session_s1'), isFalse);
  });

  group('clearForSignIn', () {
    test('another learner\'s caches are cleared and ownership moves', () async {
      SharedPreferences.setMockInitialValues({
        'cache_owner_user_id': 'user-a',
        'topic_session_s1': '{}',
      });

      await AccountDataCleaner.clearForSignIn('user-b');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('topic_session_s1'), isFalse);
      expect(prefs.getString('cache_owner_user_id'), 'user-b');
    });

    test(
      'a session that ended with no sign-out leaves nothing for the next',
      () async {
        // No owner recorded, caches present: the signed-out transition never ran.
        SharedPreferences.setMockInitialValues({'topic_session_s1': '{}'});

        await AccountDataCleaner.clearForSignIn('user-b');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('topic_session_s1'), isFalse);
      },
    );

    test('the same learner coming back keeps their caches', () async {
      SharedPreferences.setMockInitialValues({
        'cache_owner_user_id': 'user-a',
        'topic_session_s1': '{}',
      });

      await AccountDataCleaner.clearForSignIn('user-a');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('topic_session_s1'), isTrue);
    });

    test('sign-out forgets the owner', () async {
      SharedPreferences.setMockInitialValues({'cache_owner_user_id': 'user-a'});

      await AccountDataCleaner.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('cache_owner_user_id'), isFalse);
    });
  });

  test('the learner\'s in-memory cache entries go at once', () {
    final cache = LocalCacheService.instance;
    cache
      ..debugPutMemory('xp:profile:v1', {'xp': 1})
      ..debugPutMemory('proficiency:profile:v1', {})
      ..debugPutMemory('due_vocab_20', [])
      ..debugPutMemory('news:categories', []);

    cache.clearUserMemory();

    expect(cache.debugMemoryKeys, {'news:categories'});
  });
}
