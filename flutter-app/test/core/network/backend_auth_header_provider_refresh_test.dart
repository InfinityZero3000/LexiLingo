import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
import 'package:lexilingo_app/features/auth/data/models/auth_models.dart';

String _jwtExpiringIn(Duration d) {
  final exp = DateTime.now().toUtc().add(d).millisecondsSinceEpoch ~/ 1000;
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
  return 'h.$payload.s';
}

class _Storage extends Fake implements TokenStorage {
  _Storage(this.tokens);
  AuthTokens tokens;

  @override
  Future<AuthTokens?> getTokens() async => tokens;
}

void main() {
  test('a still-valid access token is sent without any refresh', () async {
    final token = _jwtExpiringIn(const Duration(minutes: 20));
    var refreshes = 0;
    final provider = BackendAuthHeaderProvider(
      tokenStorage: _Storage(AuthTokens(accessToken: token, refreshToken: 'r')),
      refreshTokens: () async {
        refreshes++;
        return true;
      },
    );

    final headers = await Future.wait([provider(), provider(), provider()]);

    expect(refreshes, 0);
    expect(headers.every((h) => h['Authorization'] == 'Bearer $token'), isTrue);
  });

  test('an expired access token refreshes before the request', () async {
    final storage = _Storage(
      AuthTokens(
        accessToken: _jwtExpiringIn(const Duration(minutes: -5)),
        refreshToken: 'r',
      ),
    );
    final fresh = _jwtExpiringIn(const Duration(minutes: 30));
    var refreshes = 0;
    final provider = BackendAuthHeaderProvider(
      tokenStorage: storage,
      refreshTokens: () async {
        refreshes++;
        storage.tokens = AuthTokens(accessToken: fresh, refreshToken: 'r2');
        return true;
      },
    );

    final headers = await provider();

    expect(refreshes, 1);
    expect(headers['Authorization'], 'Bearer $fresh');
  });
}
