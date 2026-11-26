import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
import 'package:lexilingo_app/core/services/session_expired_service.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
import 'package:lexilingo_app/features/auth/data/models/auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenStorage storage;
  late int refreshCalls;
  late http.Client client;

  // TokenStorage writes to flutter_secure_storage off the web; the plugin has
  // no implementation in a VM test, so back its channel with a plain map.
  final secureStore = <String, String>{};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            final key = args['key'] as String?;
            switch (call.method) {
              case 'write':
                secureStore[key!] = args['value'] as String;
                return null;
              case 'read':
                return secureStore[key];
              case 'delete':
                secureStore.remove(key);
                return null;
              case 'readAll':
                return Map<String, String>.from(secureStore);
              case 'deleteAll':
                secureStore.clear();
                return null;
              case 'containsKey':
                return secureStore.containsKey(key);
            }
            return null;
          },
        );
    resetTokenRefreshStateForTest();
    storage = TokenStorage();
    await storage.saveTokens(
      const AuthTokens(accessToken: 'old-access', refreshToken: 'old-refresh'),
    );

    refreshCalls = 0;
    client = MockClient((request) async {
      refreshCalls++;
      return http.Response(
        jsonEncode({
          'access_token': 'new-access-$refreshCalls',
          'refresh_token': 'new-refresh-$refreshCalls',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  });

  test('concurrent 401s share a single refresh', () async {
    final results = await Future.wait([
      refreshBackendToken(storage, httpClient: client),
      refreshBackendToken(storage, httpClient: client),
      refreshBackendToken(storage, httpClient: client),
    ]);

    expect(results, everyElement(isTrue));
    expect(refreshCalls, 1);
    expect((await storage.getTokens())!.accessToken, 'new-access-1');
  });

  test(
    'a straggler 401 reuses the fresh token instead of rotating again',
    () async {
      expect(await refreshBackendToken(storage, httpClient: client), isTrue);
      // Arrives after the refresh finished — must not spend the new refresh token.
      expect(await refreshBackendToken(storage, httpClient: client), isTrue);

      expect(refreshCalls, 1);
      expect((await storage.getTokens())!.refreshToken, 'new-refresh-1');
    },
  );

  group('a refresh the server did not answer with a verdict', () {
    http.Client answering(int status) => MockClient((_) async {
      refreshCalls++;
      return http.Response('{"detail":"x"}', status);
    });

    for (final status in [408, 429, 500, 502, 503, 504]) {
      test(
        '$status keeps the session: tokens stay, nobody is signed out',
        () async {
          var expired = 0;
          final sub = SessionExpiredService.instance.onSessionExpired.listen(
            (_) => expired++,
          );
          addTearDown(sub.cancel);

          expect(
            await refreshBackendToken(storage, httpClient: answering(status)),
            isFalse,
          );
          await Future<void>.delayed(Duration.zero);

          expect(expired, 0);
          final kept = (await storage.getTokens())!;
          expect(
            (kept.accessToken, kept.refreshToken),
            ('old-access', 'old-refresh'),
          );
        },
      );
    }

    test('a connection that fails keeps the session too', () async {
      final down = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      expect(await refreshBackendToken(storage, httpClient: down), isFalse);
      expect((await storage.getTokens())!.refreshToken, 'old-refresh');
    });

    test('a 200 without tokens is a server fault, not a sign-out', () async {
      final empty = MockClient((_) async => http.Response('{}', 200));
      expect(await refreshBackendToken(storage, httpClient: empty), isFalse);
      expect((await storage.getTokens())!.refreshToken, 'old-refresh');
    });

    test('the next refresh succeeds after a failed one', () async {
      await refreshBackendToken(storage, httpClient: answering(503));
      expect(await refreshBackendToken(storage, httpClient: client), isTrue);
      // The failed attempt was call 1; the one that worked is call 2.
      expect((await storage.getTokens())!.refreshToken, 'new-refresh-2');
    });
  });

  group('a refresh the server rejected', () {
    for (final status in [400, 401, 403]) {
      test(
        '$status ends the session: tokens and cached learner are removed',
        () async {
          await storage.saveSessionUser('{"id":"u1"}');
          var expired = 0;
          final sub = SessionExpiredService.instance.onSessionExpired.listen(
            (_) => expired++,
          );
          addTearDown(sub.cancel);

          final rejected = MockClient((_) async => http.Response('{}', status));
          expect(
            await refreshBackendToken(storage, httpClient: rejected),
            isFalse,
          );
          await Future<void>.delayed(Duration.zero);

          expect(expired, 1);
          expect(await storage.getTokens(), isNull);
          expect(await storage.readSessionUser(), isNull);
        },
      );
    }
  });

  test('the refresh token is written before the access token', () async {
    final order = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            if (call.method == 'write') order.add(args['key'] as String);
            return null;
          },
        );
    await TokenStorage().saveTokens(
      const AuthTokens(accessToken: 'a', refreshToken: 'r'),
    );
    expect(
      order.indexOf('refresh_token'),
      lessThan(order.indexOf('access_token')),
    );
  });

  test(
    'a keystore read that fails once is retried, not treated as signed out',
    () async {
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              if (call.method != 'read') return null;
              if (++reads == 1) throw PlatformException(code: 'keystore-busy');
              return 'value';
            },
          );
      expect(await TokenStorage().getAccessToken(), 'value');
      expect(reads, 2);
    },
  );

  group('another browser tab changed the stored tokens', () {
    String jwt(String sub, Duration life, String tag) {
      String part(Map<String, Object> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final exp = DateTime.now().add(life).millisecondsSinceEpoch ~/ 1000;
      return '${part({'alg': 'HS256'})}.${part({'sub': sub, 'exp': exp, 'tag': tag})}.sig';
    }

    late _TabStorage tab;
    late int expired;
    final mine = AuthTokens(
      accessToken: jwt('u1', const Duration(minutes: -5), 'mine'),
      refreshToken: 'spent-refresh',
    );

    setUp(() async {
      tab = _TabStorage(mine);
      expired = 0;
      final sub = SessionExpiredService.instance.onSessionExpired.listen(
        (_) => expired++,
      );
      addTearDown(sub.cancel);
    });

    test('its fresh tokens are used and the spent one is never sent', () async {
      tab.stored = AuthTokens(
        accessToken: jwt('u1', const Duration(minutes: 30), 'theirs'),
        refreshToken: 'their-refresh',
      );

      expect(await refreshBackendToken(tab, httpClient: client), isTrue);
      expect(refreshCalls, 0);
      expect(tab.cleared, isFalse);
    });

    test(
      'an expired pair is refreshed with the stored token, not the cached one',
      () async {
        tab.stored = AuthTokens(
          accessToken: jwt('u1', const Duration(minutes: -1), 'theirs'),
          refreshToken: 'their-refresh',
        );
        final sent = <String>[];
        final recording = MockClient((request) async {
          sent.add(
            (jsonDecode(request.body) as Map)['refresh_token'] as String,
          );
          return http.Response(
            jsonEncode({'access_token': 'a', 'refresh_token': 'r'}),
            200,
          );
        });

        expect(await refreshBackendToken(tab, httpClient: recording), isTrue);
        expect(sent, ['their-refresh']);
      },
    );

    test(
      'another account is neither adopted nor signed out of storage',
      () async {
        tab.stored = AuthTokens(
          accessToken: jwt('u2', const Duration(minutes: 30), 'other'),
          refreshToken: 'other-refresh',
        );

        expect(await refreshBackendToken(tab, httpClient: client), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(refreshCalls, 0);
        expect(expired, 1);
        expect(tab.cleared, isFalse);
      },
    );

    test(
      'every request path refuses the other account, not just refresh',
      () async {
        final tabStorage = TokenStorage();
        await tabStorage.saveTokens(mine);
        final theirs = AuthTokens(
          accessToken: jwt('u2', const Duration(minutes: 30), 'other'),
          refreshToken: 'other-refresh',
        );
        // Another tab signs in as someone else; a storage reload shows it here.
        await TokenStorage().saveTokens(theirs);

        expect(await tabStorage.getAccessToken(), isNull);
        expect(await tabStorage.getTokens(), isNull);
        expect(
          await BackendAuthHeaderProvider(tokenStorage: tabStorage)(),
          isEmpty,
        );

        // Signing this tab out leaves them signed in, and it stays refused.
        await tabStorage.clearTokens();
        expect(await TokenStorage().getAccessToken(), theirs.accessToken);
        expect(await tabStorage.getAccessToken(), isNull);

        // Signing in here again binds the tab to the new account.
        await tabStorage.saveTokens(theirs);
        expect(await tabStorage.getAccessToken(), theirs.accessToken);
      },
    );

    test('a rejection that lost the race keeps the newer tokens', () async {
      tab.stored = mine;
      final racing = MockClient((_) async {
        tab.stored = AuthTokens(
          accessToken: jwt('u1', const Duration(minutes: 30), 'theirs'),
          refreshToken: 'their-refresh',
        );
        return http.Response('{}', 401);
      });

      expect(await refreshBackendToken(tab, httpClient: racing), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(expired, 0);
      expect(tab.cleared, isFalse);
    });
  });
}

/// A tab: [cache] is what it reads, [stored] is the shared localStorage.
class _TabStorage extends Fake implements TokenStorage {
  _TabStorage(this.cache) : stored = cache;

  AuthTokens cache;
  AuthTokens stored;
  bool cleared = false;

  @override
  Future<void> reload() async => cache = stored;

  @override
  Future<AuthTokens?> getTokens() async => cleared ? null : cache;

  @override
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    cache = stored = AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  @override
  Future<void> clearTokens() async => cleared = true;
}
