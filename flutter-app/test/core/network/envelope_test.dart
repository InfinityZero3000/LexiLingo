import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/envelope.dart';

void main() {
  group('unwrapEnvelope', () {
    test('unwraps {data, meta}', () {
      expect(
        unwrapEnvelope({
          'data': {'a': 1},
          'meta': {},
        }),
        {'a': 1},
      );
    });

    test('unwraps the older {success, message, data}', () {
      expect(
        unwrapEnvelope({
          'success': true,
          'message': 'ok',
          'data': [1, 2],
        }),
        [1, 2],
      );
    });

    test('leaves a raw body and a raw list alone', () {
      final raw = {'items': [], 'total': 0};
      expect(unwrapEnvelope(raw), raw);
      expect(unwrapEnvelope([1]), [1]);
    });

    test('does not unwrap a payload that merely has a data field', () {
      final body = {'data': 1, 'name': 'x'};
      expect(unwrapEnvelope(body), body);
    });
  });

  group('extractPage', () {
    test('raw list has no total', () {
      final page = extractPage([1, 2]);
      expect(page.items, [1, 2]);
      expect(page.total, isNull);
    });

    test('{data[], pagination.total}', () {
      final page = extractPage({
        'data': [1],
        'pagination': {'total': 9},
      });
      expect(page.items, [1]);
      expect(page.total, 9);
    });

    test('{items, total} and {results, count}', () {
      expect(
        extractPage({
          'items': [1],
          'total': 4,
        }).total,
        4,
      );
      expect(
        extractPage({
          'results': [1, 2],
          'count': 2,
        }).items.length,
        2,
      );
    });

    test('an unknown body is an empty page', () {
      expect(extractPage('nope').items, isEmpty);
    });
  });
}
