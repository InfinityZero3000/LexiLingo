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
}
