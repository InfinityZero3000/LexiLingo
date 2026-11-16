import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all deployed files use one revalidating cache policy', () async {
    final config =
        jsonDecode(await File('vercel.json').readAsString())
            as Map<String, dynamic>;
    final headers = config['headers'] as List<dynamic>;
    final cacheRules = <Map<String, dynamic>>[];

    for (final rule in headers.cast<Map<String, dynamic>>()) {
      for (final header
          in (rule['headers'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        if (header['key'] == 'Cache-Control') {
          cacheRules.add({'source': rule['source'], ...header});
        }
      }
    }

    expect(cacheRules, [
      {'source': '/(.*)', 'key': 'Cache-Control', 'value': 'no-cache'},
    ]);
  });

  test('every page carries the anti-framing and no-sniff headers', () async {
    final config =
        jsonDecode(await File('vercel.json').readAsString())
            as Map<String, dynamic>;
    final rule = (config['headers'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((r) => r['source'] == '/(.*)');
    final byKey = {
      for (final h
          in (rule['headers'] as List<dynamic>).cast<Map<String, dynamic>>())
        h['key']: h['value'],
    };

    // Tokens live in localStorage on the web, so the page must not be framed.
    expect(byKey['X-Frame-Options'], 'DENY');
    expect(byKey['X-Content-Type-Options'], 'nosniff');
    // Speaking practice needs the microphone.
    expect(byKey['Permissions-Policy'], contains('microphone=(self)'));
    expect(
      byKey['Content-Security-Policy-Report-Only'],
      contains("frame-ancestors 'none'"),
    );
  });
}
