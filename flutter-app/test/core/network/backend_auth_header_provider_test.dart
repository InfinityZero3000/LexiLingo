import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';

String _tokenExpiringAt(DateTime expiry) {
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({'sub': 'user', 'exp': expiry.millisecondsSinceEpoch ~/ 1000}),
    ),
  );
  return 'header.$payload.signature';
}

void main() {
  final now = DateTime.utc(2026, 8, 14, 12);

  test('token valid for another 30 minutes is not refreshed', () {
    final token = _tokenExpiringAt(now.add(const Duration(minutes: 30)));
    expect(isAccessTokenExpiring(token, now: now), isFalse);
  });

  test('token inside the leeway window is refreshed', () {
    final token = _tokenExpiringAt(now.add(const Duration(seconds: 30)));
    expect(isAccessTokenExpiring(token, now: now), isTrue);
  });

  test('already expired token is refreshed', () {
    final token = _tokenExpiringAt(now.subtract(const Duration(minutes: 5)));
    expect(isAccessTokenExpiring(token, now: now), isTrue);
  });

  test('unparseable tokens fall back to the 401 path', () {
    expect(isAccessTokenExpiring('not-a-jwt', now: now), isFalse);
    expect(isAccessTokenExpiring('a.!!!.c', now: now), isFalse);
    expect(
      isAccessTokenExpiring(
        'a.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'u'})))}.c',
        now: now,
      ),
      isFalse,
    );
  });
}
