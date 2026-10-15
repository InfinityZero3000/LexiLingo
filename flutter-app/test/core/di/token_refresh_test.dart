import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
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
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
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

  test('a straggler 401 reuses the fresh token instead of rotating again',
      () async {
    expect(await refreshBackendToken(storage, httpClient: client), isTrue);
    // Arrives after the refresh finished — must not spend the new refresh token.
    expect(await refreshBackendToken(storage, httpClient: client), isTrue);

    expect(refreshCalls, 1);
    expect((await storage.getTokens())!.refreshToken, 'new-refresh-1');
  });
}
