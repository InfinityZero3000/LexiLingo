import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
import 'package:lexilingo_app/features/auth/data/models/auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwt(String sub) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': sub})}.sig';
}

AuthTokens _tokens(String sub) =>
    AuthTokens(accessToken: _jwt(sub), refreshToken: 'refresh-$sub');

/// Two tabs are two [TokenStorage] objects over one store: the tab of `u1`
/// is still open while another tab signs in as `u2`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  late TokenStorage first;
  late TokenStorage second;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            final key = args['key'] as String?;
            switch (call.method) {
              case 'write':
                store[key!] = args['value'] as String;
              case 'read':
                return store[key];
              case 'delete':
                store.remove(key);
            }
            return null;
          },
        );
    first = TokenStorage();
    second = TokenStorage();
    await first.saveTokens(_tokens('u1'));
    await second.saveTokens(_tokens('u2'));
    await second.saveSessionUser('{"id":"u2"}');
    await UserScopeService.setActiveUserId('u2');
  });

  test('the old tab knows the storage is no longer its own', () async {
    expect(await first.heldByAnotherAccount(), isTrue);
    expect(await second.heldByAnotherAccount(), isFalse);
  });

  test('it does not cache its learner over the other session', () async {
    await first.saveSessionUser('{"id":"u1"}');

    expect(await second.readSessionUser(), '{"id":"u2"}');
  });

  test(
    'a cached learner who does not own the stored token is ignored',
    () async {
      store['session_user'] = '{"id":"u1"}';

      expect(await second.readSessionUser(), isNull);
    },
  );

  test(
    'ending its session leaves the other account its device scope',
    () async {
      await UserScopeService.clearActiveUserId(expected: 'u1');
      expect(await UserScopeService.getActiveUserId(), 'u2');

      await UserScopeService.clearActiveUserId(expected: 'u2');
      expect(await UserScopeService.getActiveUserId(), isNull);
    },
  );
}
