import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lexilingo_app/core/network/badge_image_cache.dart';

class _Never extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

void main() {
  test(
    'badge_image_cache.dart stays free of dart:io (web threw Platform._version)',
    () {
      final source = File(
        'lib/core/network/badge_image_cache.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('dart:io')));
      expect(source, isNot(contains('io_client')));
    },
  );

  test('a stalled request times out', () async {
    final client = TimeoutHttpClient(
      timeout: const Duration(milliseconds: 20),
      inner: _Never(),
    );
    await expectLater(
      client.get(Uri.parse('https://example.test/b.png')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('the default client builds without touching dart:io types', () {
    final client = TimeoutHttpClient(timeout: const Duration(seconds: 1));
    addTearDown(client.close);
    expect(client, isA<http.BaseClient>());
  });
}
